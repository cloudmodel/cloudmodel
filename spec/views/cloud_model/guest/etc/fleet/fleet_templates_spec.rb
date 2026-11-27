require 'spec_helper'

RSpec.describe 'fleet guest templates', type: :view do
  let(:guest) { CloudModel::Guest.new name: 'fleet06' }
  let(:model) do
    CloudModel::Services::Fleet.new(admin_email: 'admin@example.com', database_password: "pa'ss", server_private_key: 'key==', enroll_secret: 'enroll-me', admin_password: 'Adm1n-pw!')
  end

  before do
    allow(guest).to receive(:external_hostname).and_return 'fleet.example.com'
    allow(model).to receive(:guest).and_return guest
  end

  def render_template name
    render template: "cloud_model/guest/#{name}", locals: { guest: guest, model: model }
    rendered
  end

  it 'renders fleet.yml as YAML for localhost database and redis' do
    config = YAML.safe_load render_template('etc/fleet/fleet_yml')
    expect(config['mysql']).to eq('address' => '127.0.0.1:3306', 'database' => 'fleet', 'username' => 'fleet', 'password' => "pa'ss")
    expect(config['redis']).to eq('address' => '127.0.0.1:6379')
    expect(config['server']).to eq('address' => '0.0.0.0:8080', 'tls' => false, 'private_key' => 'key==')
    expect(config['vulnerabilities']).to eq('databases_path' => '/var/lib/fleet/vulndb')
  end

  it 'renders the database preparation with quoted password and the migrations' do
    script = render_template('etc/fleet/prepare_db_sh')
    expect(script).to include "CREATE USER IF NOT EXISTS 'fleet'@'127.0.0.1' IDENTIFIED BY 'pa''ss';"
    expect(script).not_to include "ALTER USER 'root'"
    expect(script).to include 'runuser -u fleet -- /usr/bin/fleet prepare db --config /etc/fleet/fleet.yml --no-prompt'
    expect(script).to include 'install -d -m 750 -o fleet -g fleet /var/lib/fleet/vulndb'
  end

  it 'renders the provisioning with the token kept on the data volume' do
    script = render_template('etc/fleet/provision_sh')
    expect(script).to include 'state=/var/lib/fleet/provision'
    expect(script).to include "fleetctl setup --email admin@example.com --name Administrator \\\n      --password Adm1n-pw\\! --org-name fleet06"
    expect(script).to include 'fleetctl user create --api-only --global-role admin --name cloudmodel --email cloudmodel-api@fleet.example.com'
    expect(script).to include 'fleetctl apply -f /etc/fleet/provision.yml'
  end

  it 'renders the provisioning specs as multi-document YAML' do
    docs = YAML.safe_load_stream render_template('etc/fleet/provision_yml')
    expect(docs).to eq model.provision_specs
  end

  it 'points fleet at the port of the guest´s Percona Server' do
    guest.services << CloudModel::Services::Mysql.new(port: 3307)
    expect(YAML.safe_load(render_template('etc/fleet/fleet_yml'))['mysql']['address']).to eq '127.0.0.1:3307'
  end

  it 'points fleet at the port of the guest´s Redis' do
    guest.services << CloudModel::Services::Redis.new(port: 6380)
    expect(YAML.safe_load(render_template('etc/fleet/fleet_yml'))['redis']['address']).to eq '127.0.0.1:6380'
  end
end
