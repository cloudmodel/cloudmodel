require 'spec_helper'

describe CloudModel::Workers::Mixins::ChangeRecording do
  let(:worker_class) do
    Class.new do
      include CloudModel::Workers::Mixins::ChangeRecording
      attr_accessor :guest, :host
      def initialize(guest, host, lxc = nil)
        @guest, @host, @lxc = guest, host, lxc
      end
    end
  end

  let(:template_old) { double CloudModel::GuestTemplate, id: BSON::ObjectId.new, name: 'debian-12 old', created_at: Time.utc(2026, 7, 8) }
  let(:template_new) { double CloudModel::GuestTemplate, id: BSON::ObjectId.new, name: 'debian-12 new', created_at: Time.utc(2026, 10, 20) }
  let(:old_lxc) { double CloudModel::LxdContainer, name: 'g-20260101000000', guest_template: template_old }
  let(:new_lxc) { double CloudModel::LxdContainer, name: 'g-20261027000000', guest_template: template_new }
  let(:image) { double CloudModel::WebImage, name: 'app-stable', git_branch: 'stable', git_commit: 'abc123' }
  let(:nginx) { double CloudModel::Services::Nginx, name: 'App', deploy_web_image_id: BSON::ObjectId.new, deploy_web_image: image }
  let(:guest) { double CloudModel::Guest, id: BSON::ObjectId.new, name: 'g', services: [nginx], current_lxd_container: old_lxc, deploy_path: '/mnt/new/rootfs' }
  let(:host) { double CloudModel::Host, name: 'h1' }
  subject { worker_class.new guest, host, new_lxc }

  let(:events) { [] }
  before do
    @subscription = ActiveSupport::Notifications.subscribe('guest_deploy.cloud_model') { |*, payload| events << payload }
    allow(guest).to receive(:exec).with("sh -c #{described_class::PACKAGE_QUERY.shellescape}").and_return [true, "openssl\t3.0.13\nbash\t5.2\nexim4\t4.96\n"]
    allow(host).to receive(:exec).with("chroot /mnt/new/rootfs #{described_class::PACKAGE_QUERY}").and_return [true, "openssl\t3.0.20\nbash\t5.2\ncurl\t7.88\n"]
    allow(guest).to receive(:exec).with(/is-system-running/).and_return [true, "running\n"]
    allow(guest).to receive(:exec).with('systemctl --failed --no-legend --plain').and_return [true, '']
  end
  after { ActiveSupport::Notifications.unsubscribe @subscription }

  it 'publishes template, container, package diff, web images and smoke test of a deploy' do
    subject.begin_change_record
    subject.record_new_container
    allow(guest).to receive(:current_lxd_container).and_return new_lxc
    subject.finish_change_record

    expect(events.size).to eq 1
    event = events.first
    expect(event).to include(guest_name: 'g', host_name: 'h1', kind: 'deploy', state: 'succeeded',
                             container_before: 'g-20260101000000', container_after: 'g-20261027000000', package_count: 3)
    expect(event[:template_before][:name]).to eq 'debian-12 old'
    expect(event[:template_after][:name]).to eq 'debian-12 new'
    expect(event[:packages]).to eq added: [['curl', '7.88']], removed: [['exim4', '4.96']], changed: [['openssl', '3.0.13', '3.0.20']]
    expect(event[:web_images]).to eq [{service: 'App', image: 'app-stable', branch: 'stable', commit: 'abc123'}]
    expect(event[:checks]).to eq [{name: 'systemd running', ok: true, detail: 'running'}, {name: 'no failed units', ok: true, detail: ''}]
    expect(event[:started_at]).to be_a Time
    expect(event[:finished_at]).to be_a Time
  end

  it 'marks the deploy degraded when the smoke test finds failed units' do
    allow(guest).to receive(:exec).with(/is-system-running/).and_return [false, "degraded\n"]
    allow(guest).to receive(:exec).with('systemctl --failed --no-legend --plain').and_return [true, "nginx.service loaded failed failed A web server\n"]
    subject.begin_change_record
    subject.finish_change_record

    expect(events.first[:state]).to eq 'degraded'
    expect(events.first[:checks].last).to eq name: 'no failed units', ok: false, detail: 'nginx.service'
  end

  it 'publishes a failed deploy with its error' do
    subject.begin_change_record
    subject.fail_change_record RuntimeError.new('lxc launch failed')

    expect(events.first).to include(state: 'failed', error: 'lxc launch failed')
  end

  it 'publishes the package diff at preparation and the smoke test at the switch-over' do
    subject.begin_change_record
    subject.record_new_container
    subject.prepare_change_record
    expect(events.first).to include(state: 'prepared', kind: 'deploy')

    subject.resume_change_record
    subject.finish_change_record
    expect(events.last).to include(state: 'succeeded', kind: 'switch', container_after: 'g-20260101000000')
  end

  it 'leaves the diff empty when the running container cannot be read' do
    allow(guest).to receive(:exec).with("sh -c #{described_class::PACKAGE_QUERY.shellescape}").and_return [false, 'no such container']
    subject.begin_change_record
    subject.record_new_container
    subject.finish_change_record

    expect(events.first[:packages]).to be_nil
    expect(events.first[:package_count]).to eq 3
  end

  it 'never raises into the deploy' do
    allow(guest).to receive(:current_lxd_container).and_raise 'db gone'
    allow(CloudModel).to receive(:log_exception)
    expect { subject.begin_change_record; subject.record_new_container; subject.finish_change_record }.not_to raise_error
    expect(events).to be_empty
  end

  describe '.package_diff' do
    it 'is nil when a list is missing' do
      expect(described_class.package_diff(nil, {'a' => '1'})).to be_nil
    end
  end
end
