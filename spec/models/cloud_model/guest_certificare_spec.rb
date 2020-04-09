# encoding: UTF-8

require 'spec_helper'

describe CloudModel::GuestCertificate do
  it { expect(subject).to have_timestamps }  
    
  it { expect(subject).to have_field(:path_to_crt).of_type String }
  it { expect(subject).to have_field(:path_to_key).of_type String }
  it { expect(subject).to belong_to(:guest).of_type(CloudModel::Guest) }
  it { expect(subject).to belong_to(:certificate).of_type(CloudModel::Certificate) }
  
  describe 'name' do
    it 'should concatinate guest and certificate names' do
      allow(subject.guest).to receive(:name).and_return 'Some Guest'
      allow(subject.certificate).to receive(:name).and_return 'Some Cert'
      expect(subject.name).to eq "Some Cert Some Cert"
    end
  end
  
  describe 'to_s' do
    it 'should concatinate guest and certificate names' do
      allow(subject.guest).to receive(:name).and_return 'Some Guest'
      allow(subject.certificate).to receive(:name).and_return 'Some Cert'
      expect(subject.to_s).to eq "Guest certificate 'Some Cert Some Cert'"
    end
  end
end