require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/systemd/system/nginx_service_d/fix_perms_conf', type: :view do
  let(:model) { double 'nginx service', passenger_env: 'production' }

  def rendered_lines
    render template: 'cloud_model/guest/etc/systemd/system/nginx_service_d/fix_perms_conf', locals: { model: model, guest: nil }
    rendered.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
  end

  it 'never walks /var/www with a recursive chown in front of the start' do
    lines = rendered_lines
    expect(lines.grep(/\AExecStartPre=.*chown -R/).join).not_to include '/var/www'
    expect(lines).to include 'TimeoutStartSec=600'
    expect(lines).to include 'ExecStartPre=/bin/chown www:www /var/www /var/www/rails /var/www/rails/current /var/www/rails/current/public'
  end

  it 'fixes only wrongly owned files below /var/www, after the start and in the background' do
    post = rendered_lines.grep(/\AExecStartPost=/)
    expect(post.size).to eq 1
    cmd = post.first
    expect(cmd).to start_with 'ExecStartPost=-/bin/sh -c '
    expect(cmd).to include 'find /var/www ! -user www -exec chown -h www {} +'
    expect(cmd).to include 'find /var/www ! -group www -exec chgrp -h www {} +'
    # both walks backgrounded together, not just the last one
    expect(cmd).to match(/'\{ find .* ; find .* ; \} >\/dev\/null 2>&1 &'\z/)
    # systemd would warn about and drop unknown backslash escapes
    expect(cmd).not_to include '\\'
  end
end
