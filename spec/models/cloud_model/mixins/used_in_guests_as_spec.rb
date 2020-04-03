# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Mixins::UsedInGuestsAs do
  class TestUsedInGuestsAsModel
    include Mongoid::Document
    include CloudModel::Mixins::UsedInGuestsAs
    
    used_in_guests_as :test_item_id
  end
  
  subject { TestUsedInGuestsAsModel.new }
  
  context 'used_in_guests' do
    it 'should get guests using the test item' do
      guests = double
      
      expect(CloudModel::Guest).to receive(:where).with(test_item_id: subject.id).and_return guests
      
      expect(subject.used_in_guests).to eq guests
    end
  end
  
  context 'used_in_guests_by_host' do
    it 'should get guests ordered by host id using the test item' do
      host_ids = [BSON::ObjectId.new, BSON::ObjectId.new]
      
      guests = [
        double(host_id: host_ids[0]),
        double(host_id: host_ids[1]),
        double(host_id: host_ids[0])
      ]
      expect(subject).to receive(:used_in_guests).and_return guests
      
      expect(subject.used_in_guests_by_hosts).to eq({
        host_ids[0] => [guests[0], guests[2]],
        host_ids[1] => [guests[1]]
      }) 
    end
  end
end