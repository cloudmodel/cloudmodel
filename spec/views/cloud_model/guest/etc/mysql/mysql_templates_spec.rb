require 'spec_helper'

RSpec.describe 'percona server guest templates', type: :view do
  let(:model) { CloudModel::Services::Mysql.new }

  def render_template name
    render template: "cloud_model/guest/#{name}", locals: { model: model }
    rendered
  end

  it 'renders the server options: localhost only, root over the socket, telemetry off' do
    cnf = render_template('etc/mysql/mysql_conf_d/zz-cloudmodel_cnf')
    expect(cnf).to include "port = 3306\n"
    expect(cnf).to include "bind-address = 127.0.0.1\n"
    expect(cnf).to include "mysqlx-bind-address = 127.0.0.1\n"
    expect(cnf).to include "plugin-load-add = auth_socket.so\n"
    expect(cnf).to include "percona_telemetry_disable = 1\n"
  end

  it 'renders no Percona option for MySQL Community' do
    model.mysql_distribution = 'mysql'
    expect(render_template('etc/mysql/mysql_conf_d/zz-cloudmodel_cnf')).not_to include 'percona'
  end

  it 'renders the server options with telemetry on' do
    model.telemetry = true
    expect(render_template('etc/mysql/mysql_conf_d/zz-cloudmodel_cnf')).to include "percona_telemetry_disable = 0\n"
  end

  it 'renders the drop-in that initialises an empty data directory and switches root to the socket' do
    dropin = render_template('etc/systemd/system/mysql_service_d/cloudmodel_conf')
    expect(dropin).to include 'test -d /var/lib/mysql/mysql || /usr/sbin/mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql'
    expect(dropin).to include %q{ExecStartPost=+/usr/bin/mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket"}
  end
end
