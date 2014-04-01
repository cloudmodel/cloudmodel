# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Base do
  it { expect(subject).to be_timestamped_document }  
  
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:public_service).of_type(Mongoid::Boolean).with_default_value_of false }
  
  it { expect(subject).to be_embedded_in(:guest).of_type CloudModel::Guest }
  
  context '#service_types' do
    it "should return the default service types" do
      expect(CloudModel::Services::Base.service_types).to eq({
        mongodb: 'CloudModel::Services::Mongodb',
        nginx: 'CloudModel::Services::Nginx',
        redis: 'CloudModel::Services::Redis',
        ssh: 'CloudModel::Services::Ssh',
        tomcat: 'CloudModel::Services::Tomcat'
      })
    end
    
    it "should be configurable" do
      pending
    end
  end
  
  context 'used_ports' do
    it 'should return array with result of call to :port of the specific class' do
      subject.stub(:port).and_return(8080)
      expect(subject.used_ports).to eq [8080]
    end
  end
  
  context 'kind' do
    it 'should always return :unknown in this abstract class' do
      expect(subject.kind).to eq :unknown
    end
  end
end