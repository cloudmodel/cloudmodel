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
  
  context 'item_issue_chain' do
    it 'should return model in an Array' do
      expect(subject.item_issue_chain).to eq [subject]
    end
  end
  
  context 'linked_item_issues' do
    it 'should get issues related to the subject as Mongoid::Criteria' do
      item1 = Factory :item_issue, subject: subject
      item2 = Factory :item_issue, subject_chain: [TestHasIssuesModel.new, subject]
      item3 = Factory :item_issue, subject: TestHasIssuesModel.new
      
      result = subject.linked_item_issues
      expect(result).to be_a(Mongoid::Criteria)
      expect(result.to_a).to eq [item1, item2]
    end
  end
  
  context 'state' do
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