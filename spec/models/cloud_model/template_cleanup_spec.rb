# encoding: UTF-8

require 'spec_helper'

describe CloudModel::TemplateCleanup do
  subject(:cleanup) { described_class.new keep_per_type: 1 }

  describe 'keep sets' do
    it 'keeps the newest finished guest template per type+arch and all container-referenced ones' do
      type = CloudModel::GuestTemplateType.create!
      old        = type.templates.create! arch: 'amd64', build_state_id: 0xf0
      referenced = type.templates.create! arch: 'amd64', build_state_id: 0xf0
      newest     = type.templates.create! arch: 'amd64', build_state_id: 0xf0

      # LxdContainers are embedded in guests; bypass guest validations.
      CloudModel::Guest.collection.insert_one('lxd_containers' => [{'guest_template_id' => referenced.id}])

      expect(cleanup.keep_guest_template_ids).to include(newest.id, referenced.id)
      expect(cleanup.keep_guest_template_ids).not_to include(old.id)
      expect(cleanup.obsolete_guest_templates.to_a).to eq [old]
    end

    it 'never marks a currently building template obsolete and protects its build dir' do
      type = CloudModel::GuestTemplateType.create!
      building = type.templates.create! arch: 'amd64', build_state_id: 0x01

      expect(cleanup.obsolete_guest_templates.to_a).not_to include(building)
      expect(cleanup.busy_build_dirs).to include("/cloud/build/#{type.id}/#{building.id}")
    end

    it 'keeps core templates of kept guest templates plus the newest finished per arch' do
      core_old    = CloudModel::GuestCoreTemplate.create! arch: 'amd64', build_state_id: 0xf0
      core_in_use = CloudModel::GuestCoreTemplate.create! arch: 'amd64', build_state_id: 0xf0
      core_newest = CloudModel::GuestCoreTemplate.create! arch: 'amd64', build_state_id: 0xf0

      type = CloudModel::GuestTemplateType.create!
      kept_guest = type.templates.create! arch: 'amd64', build_state_id: 0xf0, core_template: core_in_use

      expect(cleanup.keep_guest_template_ids).to include(kept_guest.id)
      expect(cleanup.keep_core_template_ids).to include(core_newest.id, core_in_use.id)
      expect(cleanup.keep_core_template_ids).not_to include(core_old.id)
      expect(cleanup.obsolete_core_templates.to_a).to eq [core_old]
    end

    it 'keeps only the newest finished host templates per arch' do
      old    = CloudModel::HostTemplate.create! arch: 'amd64', build_state_id: 0xf0
      newest = CloudModel::HostTemplate.create! arch: 'amd64', build_state_id: 0xf0

      expect(cleanup.keep_host_template_ids).to eq [newest.id]
      expect(cleanup.obsolete_host_templates.to_a).to eq [old]
    end

    it 'honours keep_per_type' do
      generous = described_class.new keep_per_type: 2
      old, mid, newest = 3.times.map { CloudModel::HostTemplate.create! arch: 'amd64', build_state_id: 0xf0 }

      expect(generous.keep_host_template_ids).to match_array [mid.id, newest.id]
      expect(generous.obsolete_host_templates.to_a).to eq [old]
    end
  end

  describe '#cleanup!' do
    let(:output) { StringIO.new }

    it 'deletes nothing in dry run' do
      2.times { CloudModel::HostTemplate.create! arch: 'amd64', build_state_id: 0xf0 }
      allow(CloudModel::Host).to receive(:all).and_return []

      expect(File).not_to receive(:delete)
      cleanup.cleanup! dry_run: true, output: output

      expect(CloudModel::HostTemplate.count).to eq 2
      expect(output.string).to include 'Dry run'
    end

    it 'removes admin files, host copies, stale build dirs and the records when confirmed' do
      old    = CloudModel::HostTemplate.create! arch: 'amd64', build_state_id: 0xf0
      newest = CloudModel::HostTemplate.create! arch: 'amd64', build_state_id: 0xf0

      local = "#{CloudModel.config.data_directory}#{old.tarball}"
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(local).and_return true
      expect(File).to receive(:delete).with(local)

      host = double 'host', name: 'core00', deploy_state: :finished
      allow(CloudModel::Host).to receive(:all).and_return [host]
      # one stale build dir, one bogus path (must be ignored)
      allow(host).to receive(:exec).with('ls -d /cloud/build/*/* 2>/dev/null')
        .and_return [true, "/cloud/build/host/#{old.id}\n/cloud/build/../etc\n"]
      expect(host).to receive(:exec!).with("rm -f #{old.tarball}", anything)
      expect(host).to receive(:exec!).with("rm -rf #{"/cloud/build/host/#{old.id}".shellescape}", anything)

      cleanup.cleanup! dry_run: false, output: output

      expect(CloudModel::HostTemplate.where(id: old.id).count).to eq 0
      expect(CloudModel::HostTemplate.where(id: newest.id).count).to eq 1
    end
  end
end
