# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::HostTemplateWorker do
  let(:host) { Factory :host }
  subject { CloudModel::Workers::HostTemplateWorker.new host }

  before do
    allow(subject).to receive(:comment_sub_step)
    allow(subject).to receive(:chroot!)
    allow(subject).to receive(:chroot)
    allow(subject).to receive(:mkdir_p)
    allow(subject).to receive(:render_to_remote)
    allow(subject).to receive(:build_path).and_return('/cloud/build/host/test/')
    allow(host).to receive(:exec)
    allow(host).to receive(:exec!)
  end

  describe '#build_path' do
    it 'should use option build_path if given' do
      subject.instance_variable_set :@options, { build_path: '/custom/path' }
      allow(subject).to receive(:build_path).and_call_original
      expect(subject.build_path).to eq '/custom/path'
    end

    it 'should use template id based path by default' do
      template = double 'template', id: 'tmpl42'
      subject.instance_variable_set :@template, template
      subject.instance_variable_set :@options, {}
      allow(subject).to receive(:build_path).and_call_original
      expect(subject.build_path).to eq '/cloud/build/host/tmpl42/'
    end
  end

  describe '#error_log_object' do
    it 'should return the template' do
      template = double 'template'
      subject.instance_variable_set :@template, template
      expect(subject.error_log_object).to eq template
    end
  end

  describe '#install_utils' do
    it 'should install console-setup' do
      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "apt-get install console-setup -y", "Failed to install console-setup")
      subject.install_utils
    end

    it 'should install zfs' do
      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "apt-get install zfs-initramfs -y", "Failed to install zfs")
      subject.install_utils
    end
  end

  describe '#install_network' do
    it 'should install network base' do
      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "apt-get install netbase iproute2 iptables -y", "Failed to install network base")
      subject.install_network
    end

    it 'should render firewall service unit' do
      expect(subject).to receive(:render_to_remote).with(
        "/cloud_model/host/etc/systemd/system/firewall.service",
        "/cloud/build/host/test//etc/systemd/system/firewall.service"
      )
      subject.install_network
    end
  end

  describe '#install_tinc' do
    it 'should install tinc' do
      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "apt-get install tinc -y", "Failed to install tinc")
      subject.install_tinc
    end
  end

  describe '#install_lxd' do
    it 'should install LXD' do
      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "apt-get install lxd -y", "Failed to install LXD")
      subject.install_lxd
    end

    it 'should render lxcfs service unit' do
      expect(subject).to receive(:render_to_remote).with(
        "/cloud_model/host/etc/systemd/system/lxcfs.service",
        "/cloud/build/host/test//etc/systemd/system/lxcfs.service"
      )
      subject.install_lxd
    end
  end

  describe '#install_exim' do
    it 'should install exim4' do
      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "apt-get install exim4 -y", "Failed to install Exim")
      subject.install_exim
    end
  end

  describe '#install_kernel' do
    it 'should install linux kernel' do
      allow(subject).to receive(:ubuntu_arch).and_return('amd64')
      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "apt-get install --install-recommends linux-image-amd64 -y", "Failed to install linux kernel")
      subject.install_kernel
    end
  end

  describe '#install_grub' do
    it 'should install grub2' do
      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "apt-get install grub2 -y", "Failed to install Grub")
      subject.install_grub
    end

    it 'should render grub config' do
      expect(subject).to receive(:render_to_remote).with(
        "/cloud_model/host/etc/default/grub",
        "/cloud/build/host/test//etc/default/grub"
      )
      subject.install_grub
    end
  end

  describe '#install_check_mk_agent' do
    it 'should install dependencies' do
      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "apt-get install lm-sensors smartmontools -y", "Failed to install CheckMKAgent dependencies")
      subject.install_check_mk_agent
    end

    it 'should render monitoring plugins' do
      expect(subject).to receive(:render_to_remote).with(
        "/cloud_model/support/usr/lib/check_mk_agent/plugins/cgroup_cpu",
        "/cloud/build/host/test//usr/lib/check_mk_agent/plugins/cgroup_cpu",
        0755
      )
      subject.install_check_mk_agent
    end
  end

  describe '#pack_template' do
    it 'should move boot to kernel, tar, then move back' do
      template = double 'template'
      allow(template).to receive(:update_attribute)
      subject.instance_variable_set :@template, template
      allow(subject).to receive(:tar_template)

      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "mv /boot /kernel", "Failed to move boot to kernel")
      expect(subject).to receive(:tar_template).with('/cloud/build/host/test/', template)
      expect(subject).to receive(:chroot!).with('/cloud/build/host/test/', "mv /kernel /boot", "Failed to move kernal back to boot")
      subject.pack_template
    end
  end

  describe '#build_template' do
    it 'should return false if not pending and not forced' do
      template = double 'template', build_state: :running
      expect(subject.build_template(template)).to eq false
    end

    it 'should run build steps when pending' do
      template = double 'template', build_state: :pending, id: 'tmpl42'
      allow(template).to receive(:update_attributes)
      allow(subject).to receive(:os_version).and_return('ubuntu-22.04')
      allow(subject).to receive(:download_path).and_return('/cloud/downloads')
      allow(subject).to receive(:run_steps)

      expect(template).to receive(:update_attributes).with(build_state: :running, os_version: 'ubuntu-22.04')
      expect(subject).to receive(:run_steps).with(:build, anything, {})
      expect(template).to receive(:update_attributes).with(build_state: :finished, build_last_issue: "")

      expect(subject.build_template(template)).to eq template
    end
  end
end
