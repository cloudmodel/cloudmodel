# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Nginx do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 80 }
  it { expect(subject).to have_field(:ssl_supported).of_type Mongoid::Boolean }
  it { expect(subject).to have_field(:ssl_only).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:ssl_enforce).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:ssl_port).of_type(Integer).with_default_value_of(443) }
  it { expect(subject).to have_field(:ssl_certbot).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to belong_to(:ssl_cert).of_type(CloudModel::Certificate).as_inverse_of :services }

  it { expect(subject).to have_field(:passenger_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:passenger_env).of_type(String).with_default_value_of('production') }
  it { expect(subject).to have_field(:delayed_jobs_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }

  it { expect(subject).to have_field(:fastcgi_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:fastcgi_location).of_type(String).with_default_value_of('.php$') }
  it { expect(subject).to have_field(:fastcgi_pass).of_type(String).with_default_value_of('127.0.0.1:9000') }
  it { expect(subject).to have_field(:fastcgi_index).of_type(String).with_default_value_of('index.php') }

  it { expect(subject).to have_field(:capistrano_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }

  it { expect(subject).to belong_to(:deploy_web_image).of_type(CloudModel::WebImage).as_inverse_of :services }

  it { expect(subject).to have_enum(:redeploy_web_image_state).with_values(
    0x00 => :pending,
    0x01 => :running,
    0xf0 => :finished,
    0xf1 => :failed,
    0xff => :not_started
  ).with_default_value_of(:not_started) }
  it { expect(subject).to have_field(:redeploy_web_image_last_issue).of_type(String) }

  it { expect(subject).to have_field(:deploy_mongodb_host).of_type(String) }
  it { expect(subject).to have_field(:deploy_mongodb_port).of_type(Integer).with_default_value_of(27017) }
  it { expect(subject).to have_field(:deploy_mongodb_database).of_type(String) }
  it { expect(subject).to belong_to(:deploy_mongodb_replication_set).of_type(CloudModel::MongodbReplicationSet) }

  it { expect(subject).to have_field(:deploy_redis_host).of_type(String) }
  it { expect(subject).to have_field(:deploy_redis_port).of_type(Integer).with_default_value_of(6379) }
  it { expect(subject).to belong_to(:deploy_redis_sentinel_set).of_type(CloudModel::RedisSentinelSet) }

  it { expect(subject).to have_field(:daily_rake_task).of_type(String).with_default_value_of nil }

  describe 'kind' do
    it 'should return :http' do
      expect(subject.kind).to eq :http
    end
  end

  describe 'components_needed' do
    it 'should require only nginx be default' do
      expect(subject.components_needed).to eq [:nginx]
    end

    it 'should require nginx and ruby if passenger supported' do
      subject.passenger_supported = true
      expect(subject.components_needed).to eq [:ruby, :nginx]
    end

    it 'should require nginx, ruby, and additional components from deployed WebImage' do
      web_image = double CloudModel::WebImage, additional_components: ['xml', 'imagemagick']
      subject.passenger_supported = true
      allow(subject).to receive(:deploy_web_image).and_return web_image
      expect(subject.components_needed).to eq [:ruby, :nginx, :xml, :imagemagick]
    end
  end

  describe 'used_ports' do
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

  describe 'external_uri' do
    pending
  end

  describe 'internal_uri' do
    pending
  end

  describe 'status_uri' do
    pending
  end

  describe 'service_status' do
    pending
  end

  describe 'www_home' do
    it 'it should return "/var/www" for now' do
      expect(subject.www_home).to eq '/var/www'
    end
  end

  describe 'www_root' do
    it 'it should return "/var/www/rails" for now' do
      expect(subject.www_root).to eq '/var/www/rails'
    end
  end

  describe '#redeployable_redeploy_web_image_states' do
    pending
  end

  describe 'redeployable?' do
    pending
  end

  describe 'worker' do
    pending
  end

  describe 'redeploy' do
    pending
  end

  describe 'redeploy!' do
    pending
  end
end