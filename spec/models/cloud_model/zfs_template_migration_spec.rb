# encoding: UTF-8

require 'spec_helper'

describe CloudModel::ZfsTemplateMigration do
  let(:host) { Factory :host, name: 'buildhost' }
  subject(:migration) { described_class.new host }

  let(:output) { StringIO.new }
  let(:volume) { double CloudModel::BuildZfsVolume, mountpoint: '/cloud/build/type1/tmpl1', rootfs_path: '/cloud/build/type1/tmpl1/rootfs' }

  describe '#templates' do
    it 'migrates kept finished templates (cores first) and skips obsolete ones' do
      type = CloudModel::GuestTemplateType.create!
      obsolete = type.templates.create! arch: 'amd64', build_state_id: 0xf0
      # TemplateCleanup keeps the newest 2 per type + arch by default
      kept     = 2.times.map { type.templates.create! arch: 'amd64', build_state_id: 0xf0 }
      core     = CloudModel::GuestCoreTemplate.create! arch: 'amd64', build_state_id: 0xf0

      expect(migration.templates).to match_array [core] + kept
      expect(migration.templates.first).to eq core
      expect(migration.templates).not_to include obsolete
    end
  end

  describe '#migrate_template' do
    let(:template_type) { Factory :guest_template_type }
    let(:template) { Factory :guest_template, template_type: template_type, build_state: :finished }

    before do
      allow(template).to receive(:build_volume).with(host).and_return(volume)
    end

    it 'skips templates whose volume is already ready' do
      allow(volume).to receive(:ready?).and_return(true)

      expect(migration.migrate_template(template, dry_run: false, output: output)).to eq :present
      expect(output.string).to include 'already migrated'
    end

    it 'reports templates without any tarball copy' do
      allow(volume).to receive(:ready?).and_return(false)
      allow(migration).to receive(:tarball_source).with(template.tarball).and_return(nil)

      expect(migration.migrate_template(template, dry_run: false, output: output)).to eq :missing
      expect(output.string).to include 'NO TARBALL FOUND'
    end

    it 'only reports the source in dry run' do
      allow(volume).to receive(:ready?).and_return(false)
      allow(migration).to receive(:tarball_source).and_return([:host])
      expect(volume).not_to receive(:prepare!)

      expect(migration.migrate_template(template, dry_run: true, output: output)).to eq :migrated
      expect(output.string).to include '[dry-run]'
    end

    context 'with the tarball already on the host' do
      before do
        allow(volume).to receive(:ready?).and_return(false)
        allow(migration).to receive(:tarball_source).and_return([:host])
        allow(migration).to receive(:file_on_host?).and_return(false)
        allow(host).to receive(:exec!)
        allow(volume).to receive(:prepare!)
        allow(volume).to receive(:scrub_identity!)
        allow(volume).to receive(:commit!)
        allow(volume).to receive(:unmount!)
      end

      it 'unpacks the tarball into the rootfs of a fresh volume' do
        expect(volume).to receive(:prepare!)
        expect(host).to receive(:exec!).with("mkdir -p /cloud/build/type1/tmpl1/rootfs", 'Failed to create rootfs directory')
        expect(host).to receive(:exec!).with("cd /cloud/build/type1/tmpl1/rootfs && tar xzpf #{template.tarball}", 'Failed to unpack template tarball')

        migration.migrate_template template, dry_run: false, output: output
      end

      it 'unpacks the LXD metadata beside the rootfs when available' do
        allow(migration).to receive(:file_on_host?).with(host, template.lxd_image_metadata_tarball).and_return(true)
        expect(host).to receive(:exec!).with("cd /cloud/build/type1/tmpl1 && tar xzf #{template.lxd_image_metadata_tarball}", 'Failed to unpack template metadata')

        migration.migrate_template template, dry_run: false, output: output
      end

      it 'scrubs identity data, commits and records the build host' do
        expect(volume).to receive(:scrub_identity!).ordered
        expect(volume).to receive(:commit!).ordered
        expect(volume).to receive(:unmount!).ordered

        expect(migration.migrate_template(template, dry_run: false, output: output)).to eq :migrated
        expect(template.reload.build_host).to eq host
      end
    end

    it 'stages the tarball from the admin machine when missing on the host' do
      allow(volume).to receive(:ready?).and_return(false)
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(host).to receive(:ssh_address).and_return('10.0.0.1')
      allow(migration).to receive(:tarball_source).and_return([:admin, "/data#{template.tarball}"])
      allow(migration).to receive(:unpack_template)
      allow(volume).to receive(:scrub_identity!)
      allow(volume).to receive(:commit!)
      allow(volume).to receive(:unmount!)
      allow(template).to receive(:update_attributes)

      expect(host).to receive(:exec!).with("mkdir -p #{File.dirname(template.tarball)}", 'Failed to create template directory')
      expect(migration).to receive(:local_exec!).with(
        "scp -C -i /data/keys/id_rsa /data#{template.tarball} root@10.0.0.1:#{template.tarball}",
        'Failed to upload template tarball'
      )

      migration.migrate_template template, dry_run: false, output: output
    end

    it 'pipes the tarball from another host through the admin machine' do
      other = Factory :host, name: 'otherhost'
      allow(volume).to receive(:ready?).and_return(false)
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(host).to receive(:ssh_address).and_return('10.0.0.1')
      allow(other).to receive(:ssh_address).and_return('10.0.0.2')
      allow(migration).to receive(:tarball_source).and_return([:remote_host, other])
      allow(migration).to receive(:unpack_template)
      allow(volume).to receive(:scrub_identity!)
      allow(volume).to receive(:commit!)
      allow(volume).to receive(:unmount!)
      allow(template).to receive(:update_attributes)
      allow(host).to receive(:exec!)

      expect(migration).to receive(:local_exec!).with(
        "ssh -C -i /data/keys/id_rsa root@10.0.0.2 'cat #{template.tarball}' | ssh -C -i /data/keys/id_rsa root@10.0.0.1 'cat > #{template.tarball}'",
        'Failed to pipe template tarball from otherhost'
      )

      migration.migrate_template template, dry_run: false, output: output
    end

    it 'logs and reports failures without aborting the run' do
      allow(volume).to receive(:ready?).and_return(false)
      allow(migration).to receive(:tarball_source).and_return([:host])
      allow(migration).to receive(:unpack_template).and_raise('tar failed')
      expect(CloudModel).to receive(:log_exception)

      expect(migration.migrate_template(template, dry_run: false, output: output)).to eq :failed
      expect(output.string).to include 'FAILED'
    end
  end

  describe '#tarball_source' do
    let(:tarball) { '/cloud/templates/type1/tmpl1.tar.gz' }

    it 'prefers the target host' do
      allow(migration).to receive(:file_on_host?).with(host, tarball).and_return(true)

      expect(migration.tarball_source(tarball)).to eq [:host]
    end

    it 'falls back to the admin data directory' do
      allow(migration).to receive(:file_on_host?).with(host, tarball).and_return(false)
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(File).to receive(:exist?).with("/data#{tarball}").and_return(true)

      expect(migration.tarball_source(tarball)).to eq [:admin, "/data#{tarball}"]
    end

    it 'falls back to another host that still has the tarball' do
      other = Factory :host, name: 'otherhost'
      allow(migration).to receive(:file_on_host?).with(host, tarball).and_return(false)
      allow(migration).to receive(:file_on_host?).with(other, tarball).and_return(true)
      allow(File).to receive(:exist?).and_return(false)

      expect(migration.tarball_source(tarball)).to eq [:remote_host, other]
    end

    it 'returns nil when no copy exists anywhere' do
      allow(migration).to receive(:file_on_host?).and_return(false)
      allow(File).to receive(:exist?).and_return(false)

      expect(migration.tarball_source(tarball)).to be_nil
    end
  end

  describe '#migrate!' do
    it 'migrates all templates and prints a summary' do
      t1 = Factory :guest_template, template_type: Factory(:guest_template_type), build_state: :finished
      allow(migration).to receive(:templates).and_return([t1])
      allow(migration).to receive(:migrate_template).with(t1, dry_run: false, output: output).and_return(:migrated)

      results = migration.migrate! dry_run: false, output: output

      expect(results).to eq migrated: 1, present: 0, missing: 0, failed: 0
      expect(output.string).to include 'Done: 1 migrated'
    end

    it 'announces dry run' do
      allow(migration).to receive(:templates).and_return([])

      migration.migrate! dry_run: true, output: output

      expect(output.string).to include 'Dry run'
    end
  end
end
