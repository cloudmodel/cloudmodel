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
  it { expect(subject).to belong_to(:ssl_cert).of_type(CloudModel::Certificate).with_optional.as_inverse_of :services }

  it { expect(subject).to have_field(:passenger_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:passenger_env).of_type(String).with_default_value_of('production') }
  it { expect(subject).to have_field(:passenger_ruby_version).of_type(String).with_default_value_of(CloudModel.config.ruby_version) }
  it { expect(subject).to have_field(:delayed_jobs_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:delayed_jobs_queues).of_type(Array).with_default_value_of(['default']) }

  # it { expect(subject).to have_field(:fastcgi_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  # it { expect(subject).to have_field(:fastcgi_location).of_type(String).with_default_value_of('.php$') }
  # it { expect(subject).to have_field(:fastcgi_pass).of_type(String).with_default_value_of('127.0.0.1:9000') }
  # it { expect(subject).to have_field(:fastcgi_index).of_type(String).with_default_value_of('index.php') }

  it { expect(subject).to have_field(:capistrano_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_and_belong_to_many(:capistrano_ssh_groups).as_inverse_of(:services).of_type CloudModel::SshGroup }

  it { expect(subject).to have_field(:unsafe_inline_script_allowed).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:unsafe_eval_script_allowed).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:google_analytics_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:hubspot_forms_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:pingdom_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }

  it { expect(subject).to embed_many(:web_locations).of_type(CloudModel::WebLocation).as_inverse_of(:service) }
  it { expect(subject).to accept_nested_attributes_for(:web_locations) }

  it { expect(subject).to belong_to(:deploy_web_image).of_type(CloudModel::WebImage).with_optional.as_inverse_of :services }

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
  it { expect(subject).to belong_to(:deploy_mongodb_replication_set).with_optional.of_type(CloudModel::MongodbReplicationSet) }

  it { expect(subject).to have_field(:deploy_redis_host).of_type(String) }
  it { expect(subject).to have_field(:deploy_redis_port).of_type(Integer).with_default_value_of(6379) }
  it { expect(subject).to belong_to(:deploy_redis_sentinel_set).with_optional.of_type(CloudModel::RedisSentinelSet) }

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
      expect(subject.components_needed).to eq [:'ruby@3.2', :nginx]
    end

    it 'should require nginx, ruby, and additional components from deployed WebImage' do
      web_image = double CloudModel::WebImage, additional_components: ['xml', 'imagemagick']
      subject.passenger_ruby_version = '2.5'
      subject.passenger_supported = true
      allow(subject).to receive(:deploy_web_image).and_return web_image
      expect(subject.components_needed).to eq [:'ruby@2.5', :nginx, :xml, :imagemagick]
    end

    it 'should require web app components'
  end

  describe 'used_ports' do
    it 'should return http port by default' do
      expect(subject.used_ports).to eq [[80, :tcp]]
    end

    it 'should return http and https port if ssl enabled' do
      subject.ssl_supported = true
      expect(subject.used_ports).to eq [[80, :tcp], [443, :tcp]]
    end

    it 'should return https port if ssl_only' do
      subject.ssl_supported = true
      subject.ssl_only = true
      expect(subject.used_ports).to eq [[443, :tcp]]
    end

    it 'should return custom ports' do
      subject.ssl_supported = true
      subject.ssl_port = 445
      subject.port = 8080
      expect(subject.used_ports).to eq [[8080, :tcp], [445, :tcp]]
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

  describe 'content_security_policy' do
    it 'should restrict scripts source to self' do
      expect(subject.content_security_policy).to eq "script-src 'self';"
    end

    it 'should restrict scripts source to self and Google Analytics, if Google Analytics is supported' do
      subject.google_analytics_supported = true
      expect(subject.content_security_policy).to eq "script-src 'self' https://www.google-analytics.com https://ssl.google-analytics.com;"
    end

    it 'should restrict scripts source to self and Pingdom, if Pingdom is supported' do
      subject.pingdom_supported = true
      expect(subject.content_security_policy).to eq "script-src 'self' https://rum-static.pingdom.net;"
    end

    it 'should restrict scripts source to self and HubSpot forms, if HubSpot is supported' do
      subject.hubspot_forms_supported = true
      expect(subject.content_security_policy).to eq "script-src 'self' https://js.hsforms.net https://forms.hsforms.com https://www.google.com https://www.gstatic.com;"
    end

    it 'should allow inline scripts, if configured' do
      subject.unsafe_inline_script_allowed = true
      expect(subject.content_security_policy).to eq "script-src 'self' 'unsafe-inline';"
    end

    it 'should allow eval scripts, if configured' do
      subject.unsafe_eval_script_allowed = true
      expect(subject.content_security_policy).to eq "script-src 'self' 'unsafe-eval';"
    end

    it 'should restrict scripts source to self, google analytics and unsafe inline, if google analytics is supported and inline allowed' do
      subject.unsafe_inline_script_allowed = true
      subject.google_analytics_supported = true
      expect(subject.content_security_policy).to eq "script-src 'self' https://www.google-analytics.com https://ssl.google-analytics.com 'unsafe-inline';"
    end
  end

  describe 'redeploy' do
    pending
  end

  describe 'redeploy!' do
    pending
  end
end