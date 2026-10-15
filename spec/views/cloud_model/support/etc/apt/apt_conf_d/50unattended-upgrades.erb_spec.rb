require 'spec_helper'

RSpec.describe 'cloud_model/support/etc/apt/apt_conf_d/50unattended-upgrades', type: :view do
  def rendered_for(role)
    render template: 'cloud_model/support/etc/apt/apt_conf_d/50unattended-upgrades', locals: { role: role }
    rendered
  end

  it 'limits itself to the security suites of Debian and Ubuntu and never reboots' do
    out = rendered_for(:guest)
    expect(out).to include '"origin=Debian,codename=${distro_codename}-security,label=Debian-Security";'
    expect(out).to include '"origin=Ubuntu,archive=${distro_codename}-security";'
    # key=value pairs only — a bare "Ubuntu:jammy-security" aborts unattended-upgrade's parser
    out.scan(/^\s*"([^"]+)";/).flatten.each do |pattern|
      pattern.split(',').each { |pair| expect(pair).to match(/\A\w+=\S+\z/), "malformed origin pattern #{pattern}" }
    end
    expect(out).to include 'Unattended-Upgrade::Automatic-Reboot "false";'
    expect(out).not_to include 'Package-Blacklist'
  end

  it 'keeps ZFS and the kernel out of it on hosts' do
    out = rendered_for(:host)
    expect(out).to include 'Unattended-Upgrade::Package-Blacklist {'
    expect(out).to include '"zfs-dkms";'
    expect(out).to include '"linux-image-";'
  end

  it 'mails change reports to the admin when an address is configured' do
    allow(CloudModel.config).to receive(:admin_email).and_return('ops@example.com')
    out = rendered_for(:guest)
    expect(out).to include 'Unattended-Upgrade::Mail "ops@example.com";'
    expect(out).to include 'Unattended-Upgrade::MailReport "on-change";'
  end
end
