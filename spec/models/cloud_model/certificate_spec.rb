# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Certificate do
  it { expect(subject).to be_timestamped_document }  
    
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:ca).of_type String }
  it { expect(subject).to have_field(:key).of_type String }
  it { expect(subject).to have_field(:crt).of_type String }
  it { expect(subject).to have_field(:valid_thru).of_type Date }


#   scope :valid, -> { where(:valid_thru.gt => Time.now) }

  context 'to_s' do
    it 'should return the name of the Certificate' do
      subject.name = 'TestCertificate'
      expect(subject.to_s).to eq 'TestCertificate'
    end
  end

 context 'used_in_guests' do
   it 'should get all guests that has Services using this Certificate' do
     CloudModel::Guest.should_receive(:where).with('services.ssl_cert_id' => subject.id).and_return 'LIST OF GUESTS'
     expect(subject.used_in_guests).to eq 'LIST OF GUESTS'
   end
 end

  context 'used_in_guests_by_hosts' do
    it 'should sort the result of used_in_guests by host and return a Hash' do
      guests = [
        mock_model(CloudModel::Guest, host_id: 'host1'),
        mock_model(CloudModel::Guest, host_id: 'host2'),
        mock_model(CloudModel::Guest, host_id: 'host1')        
      ]    
      subject.stub(:used_in_guests) { guests }
      
      expect(subject.used_in_guests_by_hosts).to eq({
        'host1' => [guests[0], guests[2]],
        'host2' => [guests[1]],
      })
    end
  end
end