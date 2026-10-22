require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/systemd/system/mongodb_service_d/fix_perms_conf', type: :view do
  def rendered_lines
    render template: 'cloud_model/guest/etc/systemd/system/mongodb_service_d/fix_perms_conf'
    rendered.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
  end

  it 'changes only wrongly owned files of the data directory, before mongod starts' do
    lines = rendered_lines
    expect(lines.join("\n")).not_to include 'chown -R'
    expect(lines).to include 'ExecStartPre=/bin/chown mongodb:mongodb /var/lib/mongodb'
    pre = lines.grep(/\AExecStartPre=\/bin\/sh -c /)
    expect(pre.size).to eq 1
    expect(pre.first).to include 'find /var/lib/mongodb ! -user mongodb -exec chown -h mongodb {} +'
    expect(pre.first).to include 'find /var/lib/mongodb ! -group mongodb -exec chgrp -h mongodb {} +'
    # in front of the start, not backgrounded
    expect(pre.first).not_to include '&'
    expect(pre.first).not_to include '\\'
    expect(lines).to include 'TimeoutStartSec=600'
  end

  it 'keeps the resource limits' do
    expect(rendered_lines).to include('LimitNOFILE=65000', 'LimitNPROC=65000', 'LimitMEMLOCK=infinity')
  end
end
