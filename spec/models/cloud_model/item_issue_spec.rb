# encoding: UTF-8

require 'spec_helper'

describe CloudModel::ItemIssue do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:title).of_type String }
  it { expect(subject).to have_field(:message).of_type String }
  it { expect(subject).to have_field(:key).of_type String }
  it { expect(subject).to have_field(:value) }
  it { expect(subject).to have_enum(:severity).with_values(
    0x00 => :info,
    0x01 => :task,
    0x10 => :warning,
    0xf0 => :critical,
    0xff => :fatal
  ).with_default_value_of(:info) }
  it { expect(subject).to have_field(:resolved_at).of_type Time }
  it { expect(subject).to belong_to(:subject).with_polymorphism.with_optional }
  it { expect(subject).to have_field(:subject_chain_ids).of_type(Array).with_default_value_of [] }

  describe '#open' do
    it 'should filter for open items' do
      scoped = double
      filtered = double

      expect(subject.class).to receive(:scoped).and_return scoped
      expect(scoped).to receive(:where).with(resolved_at: nil).and_return filtered

      expect(subject.class.open).to eq filtered
    end
  end

  describe '#resolved' do
    it 'should filter for resolved items' do
      scoped = double
      filtered = double

      expect(subject.class).to receive(:scoped).and_return scoped
      expect(scoped).to receive(:where).with(resolved_at: {"$ne" => nil}).and_return filtered

      expect(subject.class.resolved).to eq filtered
    end
  end

  describe 'name' do
    it 'should return title' do
      subject.title = "Some Title"
      expect(subject.name).to eq "Some Title"
    end
  end

  describe 'resolved?' do
    it 'should be true if resolved_at is set' do
      subject.resolved_at = Time.now
      expect(subject.resolved?).to eq true
    end

    it 'should be false if resolved_at is not set' do
      expect(subject.resolved?).to eq false
    end
  end

  describe 'subject_chain=' do
    it 'should set subject_chain_ids' do
      guest = Factory :guest

      subject.subject_chain=[guest.host, guest]
      expect(subject.subject_chain_ids).to eq [
        {:id=>guest.host_id, :type=>"CloudModel::Host"},
        {:id=>guest.id, :type=>"CloudModel::Guest"}
      ]
    end
  end

  describe 'subject_chain' do
    it 'should get subject_chains from subject_chain_ids' do
      guest = Factory :guest

      subject.subject_chain_ids=[
        {:id=>guest.host_id, :type=>"CloudModel::Host"},
        {:id=>guest.id, :type=>"CloudModel::Guest"}
      ]
      expect(subject.subject_chain).to eq [guest.host, guest]
    end
  end

  describe 'set_subject_chain' do
    it 'should set subject chain item item_issue_chain' do
      item = Factory :guest
      subject.subject = item

      subject.set_subject_chain
      expect(subject.subject_chain).to eq [item.host, item]
    end

    it 'should set subject chain to the subject in an array if item has no item_issue_chain' do
      item = Factory :guest
      allow(item).to receive(:'respond_to?').with(:item_issue_chain, false).and_return false
      subject.subject = item

      subject.set_subject_chain
      expect(subject.subject_chain).to eq [item]
    end

    it 'should not tamper subject chain if no subject was set' do
      subject.set_subject_chain

      expect(subject.subject_chain_ids).to eq []
    end

    it 'should be called before save' do
      expect(subject).to receive(:set_subject_chain)
      subject.run_callbacks :save
    end
  end

  describe 'notify' do
    it 'should should invoke configured notifiers' do
      notifier = double
      allow(CloudModel.config).to receive(:monitoring_notifiers).and_return [{severity: [:info], notifier: notifier}]
      subject.title = "Issue Test"
      subject.message = "Just an Issue"

      expect(notifier).to receive(:send_message).with('[INFO] Issue Test', 'Just an Issue')

      subject.notify
    end

    it 'should should invoke configured notifiers and mention set subject' do
      notifier = double
      allow(CloudModel.config).to receive(:monitoring_notifiers).and_return [{severity: [:info], notifier: notifier}]
      subject.title = "Issue Test"
      subject.message = "Just an Issue on some subject"
      allow(subject).to receive(:subject).and_return 'Some::Subject'

      expect(notifier).to receive(:send_message).with('[INFO] Some::Subject: Issue Test', 'Just an Issue on some subject')

      subject.notify
    end

    it 'should should include item issue url if configured in message' do
      notifier = double
      allow(CloudModel.config).to receive(:monitoring_notifiers).and_return [{severity: [:info], notifier: notifier}]
      allow(CloudModel.config).to receive(:issue_url).and_return 'https://cloud.cloud-model.org/issues/%id%'
      subject.title = "Issue Test"
      subject.message = "Just an Issue on some subject"
      allow(subject).to receive(:subject).and_return 'Some::Subject'

      expect(notifier).to receive(:send_message).with('[INFO] Some::Subject: Issue Test', "Just an Issue on some subject\n<https://cloud.cloud-model.org/issues/#{subject.id}>")

      subject.notify
    end


    it 'should should include isubject chain if given in message' do
      notifier = double
      guest = Factory :guest
      allow(CloudModel.config).to receive(:monitoring_notifiers).and_return [{severity: [:info], notifier: notifier}]
      subject.title = "Issue Test"
      subject.message = "Just an Issue on some subject"
      subject.subject_chain_ids=[
        {:id=>guest.host_id, :type=>"CloudModel::Host"},
        {:id=>guest.id, :type=>"CloudModel::Guest"}
      ]
      allow(subject).to receive(:subject).and_return 'Some::Subject'

      expect(notifier).to receive(:send_message).with('[INFO] Some::Subject: Issue Test', "Hardware Host '#{guest.host.name}', Guest System '#{guest.name}'\n\nJust an Issue on some subject")

      subject.notify
    end

    it 'should should not invoke configured notifiers if severity is not met' do
      notifier = double
      allow(CloudModel.config).to receive(:monitoring_notifiers).and_return [{severity: [:info], notifier: notifier}]
      subject.title = "Issue Test"
      subject.severity = :task

      expect(notifier).not_to receive(:send_message)

      subject.notify
    end

    it 'should should not invoke configured notifiers if severity is not set on notifier config' do
      notifier = double
      allow(CloudModel.config).to receive(:monitoring_notifiers).and_return [{notifier: notifier}]
      subject.title = "Issue Test"
      subject.severity = :task

      expect(notifier).not_to receive(:send_message)

      subject.notify
    end

    it 'should be triggered after create' do
      expect(subject).to receive(:notify)

      subject.run_callbacks :create
    end
  end

  describe 'subject' do
    it 'should find services through it´s guest' do
      services = double
      service = double
      guest = double CloudModel::Guest, services: services

      subject.subject_type = CloudModel::Services::Nginx
      subject.subject_id = BSON::ObjectId.new

      expect(CloudModel::Guest).to receive(:find_by).with('services'=>{'$elemMatch' =>{'_id'=>subject.subject_id}}).and_return guest
      expect(services).to receive(:find).with(subject.subject_id).and_return service

      expect(subject.subject).to eq service
    end

    it 'should find services through it´s guest and fallback to nil if not found' do
      subject.subject_type = CloudModel::Services::Nginx
      subject.subject_id = BSON::ObjectId.new

      expect(subject.subject).to eq nil
    end

    it 'should find lxd_volumes through it´s guest' do
      volumes = double
      volume = double
      guest = double CloudModel::Guest, lxd_custom_volumes: volumes

      subject.subject_type = CloudModel::LxdCustomVolume
      subject.subject_id = BSON::ObjectId.new

      expect(CloudModel::Guest).to receive(:find_by).with('lxd_custom_volumes'=>{'$elemMatch' =>{'_id'=>subject.subject_id}}).and_return guest
      expect(volumes).to receive(:find).with(subject.subject_id).and_return volume

      expect(subject.subject).to eq volume
    end

    it 'should find lxd_volumes through it´s guest and fallback to nil if not found' do
      subject.subject_type = CloudModel::LxdCustomVolume
      subject.subject_id = BSON::ObjectId.new

      expect(subject.subject).to eq nil
    end

    it 'should use super subject for other items' do
      host = CloudModel::Host.new

      subject.subject = host

      expect(subject.subject).to eq host
    end

    it 'should be nil if no subject is set' do
      expect(subject.subject).to eq nil
    end
  end

  describe 'title' do
    it 'should return set title if present' do
      subject.title = "Some Title"
      expect(subject.title).to eq "Some Title"
    end

    it 'should use I18n version of title for key if no title is set, but a key' do
      subject.key = :something
      expect(subject.title).to eq "Translation missing: en.issues.something"
    end

    it 'should use I18n version of title for subject key if no title is set, but a key and subject' do
      subject.key = :something
      subject.subject = CloudModel::Host.new
      expect(subject.title).to eq "Translation missing: en.issues.cloud_model/host.something"
    end

    it 'should be blank if not key or title is set' do
      expect(subject.title).to eq nil
    end
  end
end