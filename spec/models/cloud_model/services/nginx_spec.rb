# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Nginx do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject.allow_public_service?).to eq true }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 80 }
  it { expect(subject).to embed_many(:location_overwrites).of_type(CloudModel::Services::Nginx::LocationOverwrite).as_inverse_of(:service) }

  it { expect(subject).to have_field(:ssl_supported).of_type Mongoid::Boolean }
  it { expect(subject).to have_field(:ssl_only).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:ssl_enforce).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:ssl_port).of_type(Integer).with_default_value_of(443) }
  it { expect(subject).to have_field(:ssl_certbot).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:ssl_stapling).of_type(Mongoid::Boolean).with_default_value_of(true) }
  it { expect(subject).to belong_to(:ssl_cert).of_type(CloudModel::Certificate).with_optional.as_inverse_of :services }

  it { expect(subject).to have_field(:passenger_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:passenger_env).of_type(String).with_default_value_of('production') }
  it { expect(subject).to have_field(:passenger_ruby_version).of_type(String).with_default_value_of(CloudModel.config.ruby_version) }
  it { expect(subject).to have_field(:passenger_max_pool_size).of_type(Integer).with_default_value_of(6) }
  it { expect(subject).to validate_numericality_of(:passenger_max_pool_size).greater_than(0) }
  it { expect(subject).to have_field(:delayed_jobs_supported).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { expect(subject).to have_field(:delayed_jobs_queues).of_type(Array).with_default_value_of(['default']) }

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
    0xf2 => :guest_redeploy_required,
    0xff => :not_started
  ).with_default_value_of(:not_started) }
  it { expect(subject).to have_field(:redeploy_web_image_last_issue).of_type(String) }

  it { expect(subject).to have_field(:deploy_mongodb_host).of_type(String) }
  it { expect(subject).to have_field(:deploy_mongodb_port).of_type(Integer).with_default_value_of(27017) }
  it { expect(subject).to have_field(:deploy_mongodb_database).of_type(String) }
  it { expect(subject).to belong_to(:deploy_mongodb_replication_set).with_optional.of_type(CloudModel::MongodbReplicationSet) }
  it { expect(subject).to have_field(:deploy_mongodb_write_concern).of_type(String).with_default_value_of 'majority' }
  it { expect(subject).to have_field(:deploy_mongodb_read_preference).of_type(String).with_default_value_of 'primary' }


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
      expect(subject.components_needed).to eq [:'ruby@3.4', :nginx]
    end

    it 'keeps the WebImage runtime additional_components but drops build-only toolchain (rust/clang)' do
      web_image = double CloudModel::WebImage, ruby_version: '3.4.10', additional_components: ['imagemagick', 'rust']
      subject.passenger_ruby_version = '2.5'
      subject.passenger_supported = true
      allow(subject).to receive(:deploy_web_image).and_return web_image
      expect(subject.components_needed).to eq [:'ruby@3.4.10', :nginx, :imagemagick]
    end

    it 'should require web app components' do
      web_app = double 'web_app', needed_components: [:php]
      location = double 'web_location', web_app: web_app
      allow(subject).to receive(:web_locations).and_return([location])
      expect(subject.components_needed).to include(:php)
    end
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

  let(:guest) { double CloudModel::Guest, private_address: '10.42.0.1' }
  before { allow(subject).to receive(:guest).and_return(guest) }

  describe 'external_uri' do
    it 'should return http URI by default' do
      expect(subject.external_uri).to eq 'http://10.42.0.1:80/'
    end

    it 'should return https URI when ssl supported' do
      subject.ssl_supported = true
      expect(subject.external_uri).to eq 'https://10.42.0.1:443/'
    end

    it 'should use custom ssl port' do
      subject.ssl_supported = true
      subject.ssl_port = 8443
      expect(subject.external_uri).to eq 'https://10.42.0.1:8443/'
    end
  end

  describe 'internal_uri' do
    it 'should return same as external_uri' do
      expect(subject.internal_uri).to eq subject.external_uri
    end
  end

  describe 'status_uri' do
    it 'should append /nginx_status to internal_uri' do
      expect(subject.status_uri).to eq "#{subject.internal_uri}/nginx_status"
    end
  end

  describe 'service_status' do
    it 'should return parsed nginx status on success' do
      body = "Active connections: 42\nserver accepts handled requests\n 100 100 500\nReading: 1 Writing: 2 Waiting: 39\n"
      response = double 'response', code: '200', body: body, http_version: '1.1'
      allow(Net::HTTP).to receive(:start).and_yield(double('http').tap { |h| allow(h).to receive(:request).and_return(response) })
      timing_line = "#{Time.now.to_f} 200 0.042 0.040 \"GET / HTTP/2.0\"\n"
      allow(guest).to receive(:exec).with(/tail .*timing\.log/).and_return [true, timing_line]

      result = subject.service_status
      expect(result['active']).to eq 42
      expect(result['accepted']).to eq 100
      expect(result['requests']).to eq 500
      expect(result['timing']['count']).to eq 1
      expect(result['timing']['request_ms']['max']).to eq 42.0
    end

    it 'omits timing when the timing log is not available' do
      body = "Active connections: 42\nserver accepts handled requests\n 100 100 500\nReading: 1 Writing: 2 Waiting: 39\n"
      response = double 'response', code: '200', body: body, http_version: '1.1'
      allow(Net::HTTP).to receive(:start).and_yield(double('http').tap { |h| allow(h).to receive(:request).and_return(response) })
      allow(guest).to receive(:exec).with(/tail .*timing\.log/).and_return [false, '']

      result = subject.service_status
      expect(result['active']).to eq 42
      expect(result).not_to have_key 'timing'
    end

    it 'should return error hash when connection fails' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      result = subject.service_status
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :critical
    end
  end

  describe '.aggregate_timing_lines' do
    let(:now) { Time.at 1_000_000 }
    let(:since) { now - 100 }

    def line at, status, request_time, upstream_time, request = 'GET /x HTTP/2.0'
      "#{at.to_f} #{status} #{request_time} #{upstream_time} \"#{request}\"\n"
    end

    it 'aggregates request and upstream times into percentiles' do
      lines = (1..100).map { |i| line(since + i, 200, i / 1000.0, (i / 2000.0).round(4)) }
      result = CloudModel::Services::Nginx.aggregate_timing_lines lines, since: since, now: now

      expect(result['count']).to eq 100
      expect(result['rps']).to eq 1.0
      expect(result['request_ms']['p50']).to eq 50.0
      expect(result['request_ms']['p95']).to eq 95.0
      expect(result['request_ms']['max']).to eq 100.0
      expect(result['upstream_ms']['p95']).to eq 47.5
    end

    it 'ignores entries older than since' do
      lines = [line(since - 10, 200, 0.5, 0.4), line(since + 10, 200, 0.1, 0.1)]
      result = CloudModel::Services::Nginx.aggregate_timing_lines lines, since: since, now: now

      expect(result['count']).to eq 1
      expect(result['request_ms']['max']).to eq 100.0
    end

    it 'counts error classes as rates over the window' do
      lines = [
        line(since + 1, 200, 0.1, 0.1),
        line(since + 2, 404, 0.1, '-'),
        line(since + 3, 502, 0.1, '-'),
        line(since + 4, 500, 0.1, '-')
      ]
      result = CloudModel::Services::Nginx.aggregate_timing_lines lines, since: since, now: now

      expect(result['rate_4xx']).to eq 0.01
      expect(result['rate_5xx']).to eq 0.02
    end

    it 'sums multi-upstream times and skips dashes' do
      lines = [line(since + 1, 200, 0.3, '0.100, 0.050 : 0.025')]
      result = CloudModel::Services::Nginx.aggregate_timing_lines lines, since: since, now: now

      expect(result['upstream_ms']['max']).to eq 175.0
    end

    it 'returns zero counts without request_ms for an empty window' do
      result = CloudModel::Services::Nginx.aggregate_timing_lines [], since: since, now: now

      expect(result['count']).to eq 0
      expect(result['rps']).to eq 0.0
      expect(result).not_to have_key 'request_ms'
      expect(result).not_to have_key 'upstream_ms'
    end
  end

  describe '.percentile' do
    it 'uses nearest-rank on the sorted list' do
      expect(CloudModel::Services::Nginx.percentile([1.0, 2.0, 3.0, 4.0], 50)).to eq 2.0
      expect(CloudModel::Services::Nginx.percentile([1.0, 2.0, 3.0, 4.0], 100)).to eq 4.0
      expect(CloudModel::Services::Nginx.percentile([], 95)).to eq 0.0
    end
  end

  describe 'allowed_deploy_mongodb_read_preferences' do
    it 'should return allowed read prefernce values' do
      expect(subject.allowed_deploy_mongodb_read_preferences).to eq [
        'nearest',
        'primary',
        'primary_preferred',
        'secondary',
        'secondary_preferred'
      ]
    end
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
    it 'should return finished, failed, and not_started' do
      expect(CloudModel::Services::Nginx.redeployable_redeploy_web_image_states).to eq [:finished, :failed, :guest_redeploy_required, :not_started]
    end
  end

  describe 'redeployable?' do
    it 'should return true for not_started state' do
      subject.redeploy_web_image_state = :not_started
      expect(subject.redeployable?).to eq true
    end

    it 'should return false for running state' do
      subject.redeploy_web_image_state = :running
      expect(subject.redeployable?).to eq false
    end
  end

  describe 'worker' do
    it 'should return NginxWorker instance' do
      container = double 'container'
      allow(guest).to receive(:current_lxd_container).and_return(container)
      allow(CloudModel::Workers::Services::NginxWorker).to receive(:new).with(container, subject).and_return(double('worker'))

      expect(subject.worker).to be_truthy
    end
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

  describe 'redeploy!' do
    it 'should return false if not redeployable and not pending' do
      subject.redeploy_web_image_state = :running
      expect(subject.redeploy!).to eq false
    end

    it 'should call worker redeploy_web_image when redeployable' do
      subject.redeploy_web_image_state = :not_started
      worker = double 'worker'
      allow(subject).to receive(:worker).and_return(worker)
      allow(worker).to receive(:redeploy_web_image)

      subject.redeploy!
      expect(worker).to have_received(:redeploy_web_image)
    end
  end
  describe 'ssl cert handling with certbot' do
    it 'clears a selected certificate when certbot is enabled' do
      subject.ssl_supported = true
      subject.ssl_certbot = true
      subject.ssl_cert_id = BSON::ObjectId.new

      subject.valid?
      expect(subject.ssl_cert_id).to be_nil
    end

    it 'requires a certificate for manual ssl without certbot' do
      subject.ssl_supported = true
      subject.ssl_certbot = false
      subject.ssl_cert = nil

      subject.valid?
      expect(subject.errors[:ssl_cert]).not_to be_empty
    end

    it 'does not require a certificate with certbot' do
      subject.ssl_supported = true
      subject.ssl_certbot = true

      subject.valid?
      expect(subject.errors[:ssl_cert]).to be_empty
    end
  end

end