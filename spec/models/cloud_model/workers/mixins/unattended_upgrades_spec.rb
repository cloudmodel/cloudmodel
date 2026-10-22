# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Mixins::UnattendedUpgrades do
  let(:host) { Factory :host, name: 'host01' }
  let(:guest) { Factory :guest, name: 'guest01', host: host, private_address: '10.42.0.11' }
  let(:install) { described_class::INSTALL }
  let(:check) { described_class::CHECK }
  let(:timers) { described_class::TIMERS }
  let(:sources) { described_class::SECURITY_SOURCES }
  let(:tmpl) { described_class::TEMPLATE_DIR }

  describe 'the rendered templates' do
    subject(:worker) { CloudModel::Workers::HostWorker.new host }

    # The constant names the directory with its dots, BaseWorker#render maps
    # them to underscores — one real render pins the two to each other.
    it 'render through the dotted template path for both files and roles' do
      auto = worker.send(:render, "#{tmpl}/20auto-upgrades", role: :guest)
      expect(auto).to include 'APT::Periodic::Unattended-Upgrade "1";'
      %i(host guest).each do |role|
        out = worker.send(:render, "#{tmpl}/50unattended-upgrades", role: role)
        expect(out).to include 'Unattended-Upgrade::Origins-Pattern {'
        expect(out.include?('Package-Blacklist')).to eq(role == :host)
      end
    end
  end

  describe 'template build (install_unattended_upgrades)' do
    subject(:worker) { CloudModel::Workers::GuestTemplateWorker.new host }

    before do
      allow(worker).to receive(:comment_sub_step)
      allow(worker).to receive(:chroot!)
      allow(worker).to receive(:mkdir_p)
      allow(worker).to receive(:render_to_remote)
    end

    it 'writes both apt.conf.d files for the role, then installs and verifies' do
      expect(worker).to receive(:mkdir_p).with('/mnt/build/rootfs/etc/apt/apt.conf.d').ordered
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/20auto-upgrades", '/mnt/build/rootfs/etc/apt/apt.conf.d/20auto-upgrades', 0644, role: :host).ordered
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/50unattended-upgrades", '/mnt/build/rootfs/etc/apt/apt.conf.d/50unattended-upgrades', 0644, role: :host).ordered
      expect(worker).to receive(:chroot!).with('/mnt/build/rootfs', install, 'Failed to install unattended-upgrades').ordered
      expect(worker).to receive(:chroot!).with('/mnt/build/rootfs', check, /rejected the configuration/).ordered

      worker.install_unattended_upgrades '/mnt/build/rootfs', role: :host
    end

    it 'does nothing when switched off in the configuration' do
      allow(CloudModel.config).to receive(:unattended_upgrades).and_return(false)
      expect(worker).not_to receive(:chroot!)
      expect(worker).not_to receive(:render_to_remote)

      expect(worker.install_unattended_upgrades('/mnt/build/rootfs', role: :guest)).to eq false
    end
  end

  describe '(re)deploy from a template (refresh_unattended_upgrades)' do
    subject(:worker) { CloudModel::Workers::GuestWorker.new guest }

    let(:root) { '/var/lib/lxd/containers/guest01-x/rootfs' }
    let(:upgrade) { described_class::UPGRADE }
    let(:policy) { "#{root}/usr/sbin/policy-rc.d" }

    before do
      allow(worker).to receive(:comment_sub_step)
      allow(worker).to receive(:chroot!)
      allow(worker).to receive(:chroot).and_return([true, ''])
      allow(worker).to receive(:mkdir_p)
      allow(worker).to receive(:render_to_remote)
      allow(host).to receive(:exec).and_return([true, ''])
      # no policy-rc.d in the root: config_services removed it
      allow(host).to receive(:exec).with("test -e #{policy}").and_return([false, ''])
    end

    it 'rewrites the configuration, installs the package only where it is missing, then applies the pending updates' do
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/20auto-upgrades", "#{root}/etc/apt/apt.conf.d/20auto-upgrades", 0644, role: :guest).ordered
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/50unattended-upgrades", "#{root}/etc/apt/apt.conf.d/50unattended-upgrades", 0644, role: :guest).ordered
      expect(worker).to receive(:chroot!).with(root, sources, 'Failed to add the security sources').ordered
      expect(worker).to receive(:chroot!).with(root, "test -x /usr/bin/unattended-upgrade || { #{install}; }", 'Failed to install unattended-upgrades').ordered
      expect(worker).to receive(:chroot!).with(root, check, /rejected the configuration/).ordered
      expect(worker).to receive(:chroot).with(root, upgrade).ordered.and_return([true, ''])

      expect(worker.refresh_unattended_upgrades(root, role: :guest)).to eq true
    end

    it 'keeps services from starting in the chroot during the run and removes its policy-rc.d afterwards' do
      expect(worker).to receive(:render_to_remote).with('/cloud_model/support/usr/sbin/policy-rc.d', policy, 0755).ordered
      expect(worker).to receive(:chroot).with(root, upgrade).ordered.and_return([true, ''])
      expect(host).to receive(:exec).with("rm -f #{policy}").ordered

      worker.refresh_unattended_upgrades root, role: :guest
    end

    it 'leaves a policy-rc.d that was already there alone' do
      allow(host).to receive(:exec).with("test -e #{policy}").and_return([true, ''])
      expect(worker).not_to receive(:render_to_remote).with('/cloud_model/support/usr/sbin/policy-rc.d', any_args)
      expect(host).not_to receive(:exec).with("rm -f #{policy}")

      worker.refresh_unattended_upgrades root, role: :guest
    end

    it 'does not fail the deploy when the run fails, and still removes its policy-rc.d' do
      allow(worker).to receive(:chroot).with(root, upgrade).and_return([false, 'E: mirror down'])
      expect(worker).to receive(:comment_sub_step).with(/nightly run retries/)
      expect(host).to receive(:exec).with("rm -f #{policy}")

      expect(worker.refresh_unattended_upgrades(root, role: :guest)).to eq false
    end

    it 'refreshes the package lists first, tolerating a broken list, and runs unattended-upgrade for real' do
      expect(upgrade).to match(/\Aapt-get update -q \|\| echo .*; \/usr\/bin\/unattended-upgrade -v\z/)
      expect(upgrade).not_to include '--dry-run'
    end

    it 'is a deploy step of the guest worker and of the host deploy' do
      expect(CloudModel::Workers::GuestWorker.instance_method(:deploy).source).to include "['Ensure unattended security upgrades', :ensure_unattended_upgrades]"
      expect(CloudModel::Workers::HostWorker.instance_methods).to include :refresh_unattended_upgrades
      expect(File.read(CloudModel::Workers::HostWorker.instance_method(:deploy).source_location.first)).to include 'refresh_unattended_upgrades root, role: :host'
    end
  end

  describe 'live push to a host (deploy_unattended_upgrades_to_host)' do
    subject(:worker) { CloudModel::Workers::HostWorker.new host }

    before do
      allow(worker).to receive(:comment_sub_step)
      allow(worker).to receive(:mkdir_p)
      allow(worker).to receive(:render_to_remote)
      allow(host).to receive(:exec!)
    end

    it 'writes both files in place, installs over ssh, verifies and enables the timers' do
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/20auto-upgrades", '/etc/apt/apt.conf.d/20auto-upgrades', 0644, role: :host).ordered
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/50unattended-upgrades", '/etc/apt/apt.conf.d/50unattended-upgrades', 0644, role: :host).ordered
      expect(host).to receive(:exec!).with("sh -c #{sources.shellescape}", 'Failed to add the security sources on host01').ordered
      expect(host).to receive(:exec!).with(install, 'Failed to install unattended-upgrades on host01').ordered
      expect(host).to receive(:exec!).with(check, /rejected the configuration on host01/).ordered
      expect(host).to receive(:exec!).with(timers, 'Failed to enable the apt timers').ordered

      worker.deploy_unattended_upgrades_to_host
    end
  end

  describe 'live push to a guest (deploy_unattended_upgrades_to_guest)' do
    subject(:worker) { CloudModel::Workers::GuestWorker.new guest }
    let(:container) { double CloudModel::LxdContainer, name: 'guest01-20260101000000', blank?: false }

    before do
      allow(worker).to receive(:comment_sub_step)
      allow(worker).to receive(:render_to_remote)
      allow(guest).to receive(:current_lxd_container).and_return(container)
      allow(guest).to receive(:exec!)
      allow(host).to receive(:exec!)
      allow(host).to receive(:exec)
      allow(SecureRandom).to receive(:hex).and_return('abcd')
    end

    it 'pushes both files as container root, installs inside the container through a shell, verifies and enables the timers' do
      %w(20auto-upgrades 50unattended-upgrades).each do |file|
        expect(worker).to receive(:render_to_remote).with("#{tmpl}/#{file}", "/tmp/cloud_model_apt_guest01-20260101000000_#{file}_abcd", 0644, role: :guest)
        expect(host).to receive(:exec!).with("lxc file push /tmp/cloud_model_apt_guest01-20260101000000_#{file}_abcd guest01-20260101000000/etc/apt/apt.conf.d/#{file} --uid 0 --gid 0 --mode 0644", "Failed to push #{file} to guest01-20260101000000")
        expect(host).to receive(:exec).with("rm -f /tmp/cloud_model_apt_guest01-20260101000000_#{file}_abcd")
      end
      expect(guest).to receive(:exec!).with("sh -c #{sources.shellescape}", 'Failed to add the security sources in guest01-20260101000000').ordered
      expect(guest).to receive(:exec!).with("sh -c #{install.shellescape}", 'Failed to install unattended-upgrades in guest01-20260101000000').ordered
      expect(guest).to receive(:exec!).with("sh -c #{check.shellescape}", /rejected the configuration in guest01-20260101000000/).ordered
      expect(guest).to receive(:exec!).with(timers, 'Failed to enable the apt timers in guest01-20260101000000').ordered

      worker.deploy_unattended_upgrades_to_guest
    end

    it 'refuses without a running container' do
      allow(guest).to receive(:current_lxd_container).and_return(nil)
      expect { worker.deploy_unattended_upgrades_to_guest }.to raise_error(/no running LXD container/)
    end
  end

  describe 'SECURITY_SOURCES' do
    # Runs the snippet for real against a scratch /etc.
    def run_sources os_release, sources_list, extra = {}
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p "#{dir}/etc/apt/sources.list.d"
        File.write "#{dir}/etc/os-release", os_release
        File.write "#{dir}/etc/apt/sources.list", sources_list
        extra.each { |name, content| File.write "#{dir}/etc/apt/sources.list.d/#{name}", content }
        script = described_class::SECURITY_SOURCES.gsub('/etc/', "#{dir}/etc/")
        2.times { expect(system('sh', '-c', script)).to eq true }
        File.read "#{dir}/etc/apt/sources.list"
      end
    end

    let(:bookworm) { "ID=debian\nVERSION_CODENAME=bookworm\n" }
    let(:base) { "deb http://ftp.de.debian.org/debian bookworm contrib main\n" }

    it 'adds the missing -security and -updates suites on Debian, once' do
      expect(run_sources(bookworm, base)).to eq base +
        "deb http://security.debian.org/debian-security bookworm-security main contrib\n" \
        "deb http://ftp.de.debian.org/debian bookworm-updates main contrib\n"
    end

    it 'leaves suites alone that are there already, also in deb822 sources' do
      deb822 = "Types: deb\nURIs: http://deb.debian.org/debian\nSuites: bookworm bookworm-updates\n"
      expect(run_sources(bookworm, base, 'debian.sources' => deb822)).to eq base +
        "deb http://security.debian.org/debian-security bookworm-security main contrib\n"
    end

    it 'does not touch Ubuntu or Debian releases with the old security suite name' do
      expect(run_sources("ID=ubuntu\nVERSION_CODENAME=jammy\n", "deb http://archive.ubuntu.com/ubuntu jammy main\n")).to eq "deb http://archive.ubuntu.com/ubuntu jammy main\n"
      expect(run_sources("ID=debian\nVERSION_CODENAME=buster\n", "deb http://deb.debian.org/debian buster main\n")).to eq "deb http://deb.debian.org/debian buster main\n"
    end
  end

  it 'tolerates a failing apt-get update but not a failing install, and waits for the dpkg lock' do
    expect(install).to match(/apt-get update -q \|\| echo .*; DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=600 unattended-upgrades\z/)
    expect(check).to start_with 'apt-config dump >/dev/null && /usr/bin/unattended-upgrade --dry-run'
  end
end
