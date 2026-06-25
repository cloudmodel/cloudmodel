# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Mixins::HasIssues do
  class TestHasIssuesModel
    include Mongoid::Document
    include CloudModel::Mixins::HasIssues
  end
  
  subject { TestHasIssuesModel.new }
  
  it { expect(subject).to have_field(:monitoring_last_check_at).of_type Time}
  it { expect(subject).to have_field(:monitoring_last_check_result).of_type(Hash).with_default_value_of({})}
  it { expect(subject).to have_many(:item_issues).of_type CloudModel::ItemIssue}
  
  describe 'item_issue_chain' do
    it 'should return model in an Array' do
      expect(subject.item_issue_chain).to eq [subject]
    end
  end
  
  describe 'linked_item_issues' do
    it 'should get issues related to the subject as Mongoid::Criteria' do
      item1 = Factory :item_issue, subject: subject
      item2 = Factory :item_issue, subject_chain: [TestHasIssuesModel.new, subject]
      item3 = Factory :item_issue, subject: TestHasIssuesModel.new
      
      result = subject.linked_item_issues
      expect(result).to be_a(Mongoid::Criteria)
      expect(result.to_a).to eq [item1, item2]
    end
  end
  
  describe 'monitoring_samples' do
    it 'should find samples recorded for the subject' do
      sample = CloudModel::MonitoringSample.create!(
        subject_type: subject.class.name, subject_id: subject.id,
        resolution: 'raw', ref_at: Time.now, metrics: {'a' => 1.0}
      )
      CloudModel::MonitoringSample.create!(
        subject_type: subject.class.name, subject_id: BSON::ObjectId.new,
        resolution: 'raw', ref_at: Time.now, metrics: {'a' => 2.0}
      )

      expect(subject.monitoring_samples.to_a).to eq [sample]
    end
  end

  describe 'monitoring_history' do
    def sample(resolution, ref_at)
      CloudModel::MonitoringSample.create!(
        subject_type: subject.class.name, subject_id: subject.id,
        resolution: resolution, ref_at: ref_at, metrics: {'a' => 1.0}
      )
    end

    it 'should filter by resolution and time window, ordered by time' do
      old_raw = sample('raw', Time.now - 2.hours)
      new_raw = sample('raw', Time.now - 10.minutes)
      sample('hour', Time.now - 10.minutes)

      result = subject.monitoring_history(resolution: 'raw', since: Time.now - 1.hour)
      expect(result).to be_a(Mongoid::Criteria)
      expect(result.to_a).to eq [new_raw]
    end

    it 'should default to raw resolution and return all when no bounds given' do
      a = sample('raw', Time.now - 2.hours)
      b = sample('raw', Time.now - 10.minutes)
      expect(subject.monitoring_history.to_a).to eq [a, b]
    end
  end

  describe 'state' do
    it 'should be :undefined without a monitoring_last_check_result' do
      expect(subject.state).to eq :undefined
    end
    
    it 'should be :running if no issues where found' do
      subject.monitoring_last_check_result = {state: :ok}
      expect(subject.state).to eq :running
    end
    
    it 'should be :highest severity if issues where found' do
      subject.monitoring_last_check_result = {state: :oops}
     
      Factory :item_issue, subject: subject, severity: :warning         
      expect(subject.state).to eq :warning

      Factory :item_issue, subject: subject, severity: :fatal         
      expect(subject.state).to eq :fatal
    end
  end
end