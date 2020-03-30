# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Nginx do
  it { expect(subject).to be_a CloudModel::Services::Base }
  
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 80 }
  it { expect(subject).to have_field(:ssl_supported).of_type Mongoid::Boolean }
  it { expect(subject).to have_field(:ssl_only).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:ssl_enforce).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:ssl_port).of_type(Integer).with_default_value_of(443) }
  it { expect(subject).to belong_to(:ssl_cert).of_type(CloudModel::Certificate).as_inverse_of :services }
  
  it { expect(subject).to have_field(:passenger_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:passenger_env).of_type(String).with_default_value_of('production') }
  
  it { expect(subject).to have_field(:capistrano_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  
  it { expect(subject).to belong_to(:deploy_web_image).of_type(CloudModel::WebImage).as_inverse_of :services }
  
  it { expect(subject).to have_field(:deploy_mongodb_host).of_type(String) }
  it { expect(subject).to have_field(:deploy_mongodb_port).of_type(Integer).with_default_value_of(27017) }
  it { expect(subject).to have_field(:deploy_mongodb_database).of_type(String) }

  it { expect(subject).to have_field(:deploy_redis_host).of_type(String) }
  it { expect(subject).to have_field(:deploy_redis_port).of_type(Integer).with_default_value_of(6379) }

  it { expect(subject.kind).to eq :http }
  
  context 'www_home' do
    it 'it should return "/var/www" for now' do
      expect(subject.www_home).to eq '/var/www'
    end
  end
  
  context 'www_root' do
    it 'it should return "/var/www/rails" for now' do
      expect(subject.www_root).to eq '/var/www/rails'
    end
  end
  
  context 'used_ports' do
    it 'should return http port by default' do
      expect(subject.used_ports).to eq [80]
    end
    
    it 'should return http and https port if ssl enabled' do
      subject.ssl_supported = true
      expect(subject.used_ports).to eq [80, 443]
    end
    
    it 'should return https port if ssl_only' do
      subject.ssl_supported = true
      subject.ssl_only = true
      expect(subject.used_ports).to eq [443]
    end
    
    it 'should return custom ports' do
      subject.ssl_supported = true
      subject.ssl_port = 445
      subject.port = 8080
      expect(subject.used_ports).to eq [8080, 445] 
    end
  end
end