require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/nginx/sites-available/cloudmodel_conf', type: :view do
  let(:host) { CloudModel::Host.new }
  let(:guest) { CloudModel::Guest.new host: host, external_hostname: 'www.example.com' }
  let(:model) { CloudModel::Services::Nginx.new guest: guest, ssl_supported: true, ssl_cert: CloudModel::Certificate.new }

  def render_conf
    render template: 'cloud_model/guest/etc/nginx/sites-available/cloudmodel_conf', locals: { guest: guest, model: model, certbot_cert_available: false }
  end

  it 'renders the TLS listener with HTTP/2 by default' do
    render_conf

    expect(rendered).to match(/^\s*listen\s+443 ssl http2 deferred;$/)
    expect(rendered).to match(/^\s*listen\s+80;$/)
  end

  it 'renders the request body limit in megabytes, 0 as unlimited' do
    render_conf
    expect(rendered).to match(/^\s*client_max_body_size\s+600M;$/)

    model.client_max_body_size = 0
    render_conf
    expect(rendered).to match(/^\s*client_max_body_size\s+0;$/)
  end

  it 'renders the TLS listener without HTTP/2 when the option is off' do
    model.http2 = false
    render_conf

    expect(rendered).to match(/^\s*listen\s+443 ssl deferred;$/)
    expect(rendered).not_to include 'http2'
  end

  describe 'additional MIME types' do
    it 'adds them in an http-level types block' do
      model.additional_mime_types = { 'xsd' => 'application/xml' }
      render_conf

      expect(rendered).to match(%r{^types \{\n\s+application/xml\s+xsd;\n\}$})
      expect(rendered.index('types {')).to be < rendered.index('server {')
    end

    it 'renders no types block without them' do
      render_conf

      expect(rendered).not_to include 'types {'
    end
  end

  describe 'ssl_enforce exceptions' do
    before do
      model.ssl_enforce = true
      model.ssl_enforce_exceptions = ['/schema/']
    end

    it 'serves the listed prefixes on plain http from the document root, the rest still redirects' do
      render_conf
      http_server = rendered[/server \{\n\s*listen\s+80;.*?\n\}/m]

      expect(http_server).to include 'rewrite'
      expect(http_server).to match(%r{location \^~ /schema/ \{\n\s*root\s+/var/www/rails/current/public/;\n\s*try_files\s+\$uri =404;\n\s*\}})
    end

    it 'keeps the basic auth on the exception' do
      model.basic_auth_supported = true
      model.basic_auth_users.build name: 'demo', password: 'opensesame'
      render_conf
      http_server = rendered[/server \{\n\s*listen\s+80;.*?\n\}/m]

      expect(http_server).to match(%r!location \^~ /schema/ \{[^}]*auth_basic\s+\$cloudmodel_basic_auth;!m)
    end

    it 'renders no exception location while https is not enforced (http serves everything anyway)' do
      model.ssl_enforce = false
      render_conf

      expect(rendered).not_to include 'location ^~ /schema/'
    end
  end

  describe 'basic auth' do
    before do
      allow(CloudModel.config).to receive(:tinc_network).and_return '10.44.0.0/16'
      model.basic_auth_supported = true
      model.basic_auth_realm = 'Staging'
      model.basic_auth_users.build name: 'demo', password: 'opensesame'
    end

    it 'renders nothing of it while the option is off' do
      model.basic_auth_supported = false
      render_conf

      expect(rendered).not_to include 'auth_basic'
      expect(rendered).not_to include 'cloudmodel_basic_auth'
    end

    it 'puts the auth in front of both listeners, with the realm from the map' do
      model.ssl_enforce = false
      render_conf

      expect(rendered.scan(/^\s*auth_basic\s+\$cloudmodel_basic_auth;$/).size).to eq 2
      expect(rendered.scan(%r{^\s*auth_basic_user_file\s+/etc/nginx/\.htpasswd;$}).size).to eq 2
      expect(rendered).to match(/^\s*default\s+"Staging";$/)
    end

    it 'leaves the https redirect of an enforced TLS site without auth' do
      model.ssl_enforce = true
      render_conf

      expect(rendered.scan(/^\s*auth_basic\s+\$cloudmodel_basic_auth;$/).size).to eq 1
    end

    it 'lets the private network and the ACME challenge pass' do
      render_conf

      expect(rendered).to match(%r{^\s*10\.44\.0\.0/16\s+private;$})
      expect(rendered).to match(/^\s*~\^private:\s+off;$/)
      expect(rendered).to match(%r{^\s*~\^outside:/\\\.well-known/acme-challenge/ off;$})
    end

    it 'asks the private network for a login too without the bypass' do
      model.basic_auth_private_network_bypass = false
      render_conf

      expect(rendered).not_to include 'private;'
      expect(rendered).to match(%r{acme-challenge/ off;})
    end

    it 'keeps the monitoring status page open' do
      render_conf

      expect(rendered).to match(%r{location /nginx_status \{\n\s*stub_status\s+on;\n\s*access_log\s+off;\n\s*auth_basic\s+off;})
    end

    it 'does not use allow/deny, so the locations keep their own access rules' do
      render_conf

      expect(rendered).not_to match(/^\s*satisfy/)
    end
  end
end
