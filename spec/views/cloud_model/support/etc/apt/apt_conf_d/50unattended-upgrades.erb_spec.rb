require 'spec_helper'

RSpec.describe 'cloud_model/support/etc/apt/apt_conf_d/50unattended-upgrades', type: :view do
  def rendered_for(role)
    render template: 'cloud_model/support/etc/apt/apt_conf_d/50unattended-upgrades', locals: { role: role }
    rendered
  end

  def origins_patterns(out)
    out[/Origins-Pattern \{(.*?)\};/m, 1].scan(/^\s*"([^"]+)";/).flatten
  end

  it 'limits itself to the security suites of Debian and Ubuntu and never reboots' do
    out = rendered_for(:guest)
    expect(out).to include '"origin=Debian,codename=${distro_codename}-security,label=Debian-Security";'
    expect(out).to include '"origin=Ubuntu,archive=${distro_codename}-security";'
    expect(out).to include 'Unattended-Upgrade::Automatic-Reboot "false";'
    expect(out).not_to include 'Package-Blacklist'
    # the Debian default; "true" would act as a daily autoremove
    expect(out).not_to include 'Remove-Unused-Dependencies'
  end

  it 'lets the php maintainer repositories through, which carry the php security releases' do
    out = rendered_for(:guest)
    expect(out).to include '"origin=deb.sury.org,suite=${distro_codename}";'
    expect(out).to include '"origin=LP-PPA-ondrej-php,suite=${distro_codename}";'
  end

  it 'uses key=value origin patterns only, for both roles' do
    # a bare "Ubuntu:jammy-security" aborts unattended-upgrade's parser
    %i(host guest).each do |role|
      patterns = origins_patterns(rendered_for(role))
      expect(patterns.size).to be >= 5
      patterns.each do |pattern|
        pattern.split(',').each { |pair| expect(pair).to match(/\A\w+=\S+\z/), "malformed origin pattern #{pattern} (#{role})" }
      end
    end
  end

  it 'keeps ZFS, its libraries and the kernel out of it on hosts' do
    out = rendered_for(:host)
    expect(out).to include 'Unattended-Upgrade::Package-Blacklist {'
    %w(zfs-dkms zfsutils-linux zfs-initramfs zfs-zed libzfs libzpool libnvpair libuutil linux-image- linux-headers-).each do |entry|
      expect(out).to include %("#{entry}";)
    end
  end

  it 'writes the admin address verbatim, not HTML-escaped' do
    allow(CloudModel.config).to receive(:admin_email).and_return("o'ps@example.com")
    expect(rendered_for(:host)).to include %(Unattended-Upgrade::Mail "o'ps@example.com";)
  end

  it 'mails change reports to the admin when an address is configured' do
    allow(CloudModel.config).to receive(:admin_email).and_return('ops@example.com')
    out = rendered_for(:guest)
    expect(out).to include 'Unattended-Upgrade::Mail "ops@example.com";'
    expect(out).to include 'Unattended-Upgrade::MailReport "on-change";'
  end
end
