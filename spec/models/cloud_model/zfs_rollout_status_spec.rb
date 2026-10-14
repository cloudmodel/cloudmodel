# encoding: UTF-8

require 'spec_helper'

describe CloudModel::ZfsRolloutStatus do
  let(:host) { Factory :host, name: 'host01' }
  let(:output) { StringIO.new }

  # Declared before the let! guests: creating a container would otherwise
  # run `lxc init` on the host via SSH.
  before do
    allow_any_instance_of(CloudModel::LxdContainer).to receive(:create_container)
  end
  # Given explicitly: resolving one via Guest#template would build it.
  let(:guest_template) { Factory :guest_template }

  let!(:legacy_guest) do
    guest = Factory :guest, name: 'old-guest', host: host, private_address: '10.42.0.11'
    container = guest.lxd_containers.create! guest_template: guest_template, created_at: Time.now, rootfs_origin: 'image'
    guest.update_attribute :current_lxd_container_id, container.id
    guest
  end

  let!(:zfs_guest) do
    guest = Factory :guest, name: 'new-guest', host: host, private_address: '10.42.0.12'
    container = guest.lxd_containers.create! guest_template: guest_template, created_at: Time.now, rootfs_origin: 'template_volume'
    guest.update_attribute :current_lxd_container_id, container.id
    guest
  end

  let!(:unknown_guest) do
    guest = Factory :guest, name: 'unknown-guest', host: host, private_address: '10.42.0.13'
    container = guest.lxd_containers.create! guest_template: guest_template, created_at: Time.now
    guest.update_attribute :current_lxd_container_id, container.id
    guest
  end

  before do
    allow(CloudModel::Host).to receive(:all).and_return([host])
    allow(CloudModel::WebImage).to receive(:all).and_return([])
    allow(host).to receive(:exec).and_return([false, ''])
  end

  describe '#guest_rows' do
    it 'reports the recorded container layout of every guest on the host' do
      rows = described_class.new(probe: false).guest_rows
      expect(rows.map { |r| [r[:guest].name, r[:origin]] }).to eq [
        ['new-guest', 'template_volume'],
        ['old-guest', 'image'],
        ['unknown-guest', nil]
      ]
    end

    it 'does not touch the hosts without probe' do
      expect(host).not_to receive(:exec)
      described_class.new(probe: false).guest_rows
    end

    it 'probes the host for containers with unknown layout and persists the answer' do
      allow(host).to receive(:exec).with(/zfs get -H -o value origin guests\/containers\/unknown-guest-/).and_return([true, "-\n"])

      rows = described_class.new(probe: true).guest_rows
      expect(rows.detect { |r| r[:guest].name == 'unknown-guest' }[:origin]).to eq 'image'
      expect(unknown_guest.reload.current_lxd_container.rootfs_origin).to eq 'image'
    end
  end

  describe '#legacy_guests' do
    it 'lists the guests that need a one-time guest redeploy' do
      expect(described_class.new(probe: false).legacy_guests.map { |r| r[:guest] }).to eq [legacy_guest]
    end
  end

  describe '#template_rows' do
    it 'flags guests without any finished template for their type' do
      rows = described_class.new(probe: false).template_rows
      expect(rows.size).to eq 1
      expect(rows.first[:template]).to be_nil
      expect(rows.first[:guests]).to match_array [legacy_guest, zfs_guest, unknown_guest]
    end

    context 'with a finished template for the guests´ type' do
      let!(:template) do
        type = CloudModel::GuestTemplateType.create! components: legacy_guest.components_needed, os_version: legacy_guest.os_version
        type.templates.create! arch: host.arch, build_state_id: 0xf0
      end

      it 'resolves the template a redeploy would clone without building anything' do
        expect_any_instance_of(CloudModel::GuestTemplateType).not_to receive(:build_new_template!)

        rows = described_class.new(probe: false).template_rows
        expect(rows.size).to eq 1
        expect(rows.first[:template]).to eq template
        expect(rows.first[:volume_ready]).to eq false
      end

      it 'checks the build volume on the host when probing' do
        volume = double CloudModel::BuildZfsVolume, ready?: true
        allow_any_instance_of(CloudModel::GuestTemplate).to receive(:build_volume).with(host).and_return(volume)

        rows = described_class.new(probe: true).template_rows
        expect(rows.first[:volume_ready]).to eq true
      end
    end
  end

  describe '#web_image_rows' do
    it 'reports one row per image and arch with the built artifact version' do
      image = double 'WebImage', name: 'app', build_targets: ['amd64', 'arm64']
      allow(image).to receive(:artifact_version).with('amd64').and_return('20260101000000')
      allow(image).to receive(:artifact_version).with('arm64').and_return(nil)
      allow(CloudModel::WebImage).to receive(:all).and_return([image])

      rows = described_class.new(probe: false).web_image_rows
      expect(rows.map { |r| [r[:arch], r[:version]] }).to eq [['amd64', '20260101000000'], ['arm64', nil]]
    end

    it 'surfaces images whose guests disagree on the base OS instead of raising' do
      image = double 'WebImage', name: 'app'
      allow(image).to receive(:build_targets).and_raise('consuming guests disagree on os_version')
      allow(CloudModel::WebImage).to receive(:all).and_return([image])

      rows = described_class.new(probe: false).web_image_rows
      expect(rows.first[:error]).to include 'disagree'
    end
  end

  describe '#report' do
    it 'prints the legacy guests and what to do about them' do
      described_class.new(probe: false).report output: output

      expect(output.string).to include 'host01/old-guest: IMAGE (legacy) — one full guest redeploy required'
      expect(output.string).to include 'host01/new-guest: template volume'
      expect(output.string).to include 'host01/unknown-guest: unknown'
      expect(output.string).to include '3 guests, 1 on the legacy image layout, 1 unknown'
      expect(output.string).to include 'rollouts to them are refused'
    end
  end
end
