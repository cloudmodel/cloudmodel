require 'spec_helper'

describe CloudModel::Config do
  describe 'initialize' do
    it 'should return new config' do
      expect(CloudModel::Config.new).to be_a CloudModel::Config
    end

    it 'should take optional block and pass it to configure' do
      b = Proc.new{}

      expect_any_instance_of(CloudModel::Config).to receive(:configure) { |&block| expect(block).to be(b) }
      CloudModel::Config.new(&b)
    end
  end

  describe 'configure' do
    it 'should yield with config instance' do
      expect { |b| subject.configure &b }.to yield_with_args(subject)
    end
  end

  describe 'data_directory' do
    it 'should allow to set data directory' do
      subject.data_directory = '/my/data/dir'
      expect(subject.data_directory).to eq '/my/data/dir'
    end

    it 'should default to Rails root /data' do
      expect(subject.data_directory).to eq "#{Rails.root}/data"
    end
  end

  describe 'backup_directory' do
    it 'should allow to set backup directory' do
      subject.backup_directory = '/my/data/dir'
      expect(subject.backup_directory).to eq '/my/data/dir'
    end

    it 'should default to Rails root /data/backups' do
      expect(subject.backup_directory).to eq "#{Rails.root}/data/backups"
    end
  end

  describe 'bundle_command' do
    it 'should allow to set bundle command' do
      subject.bundle_command = '/my_bin/bundle'
      expect(subject.bundle_command).to eq '/my_bin/bundle'
    end

    it 'should default to "PATH=/bin:/sbin:/usr/bin:/usr/local/bin bundle"' do
      expect(subject.bundle_command).to eq "PATH=/usr/local/bin:/bin:/sbin:/usr/bin bundle"
    end
  end

  describe 'skip_sync_images' do
    it 'should allow to set options to skip sync images' do
      subject.skip_sync_images = true
      expect(subject.skip_sync_images).to eq true
    end

    it 'should default to false' do
      expect(subject.skip_sync_images).to eq false
    end
  end

  describe 'use_external_ip' do
    it 'should allow to set options to use external ip' do
      subject.use_external_ip = true
      expect(subject.use_external_ip).to eq true
    end

    it 'should default to false' do
      expect(subject.use_external_ip).to eq false
    end
  end

  describe 'dns_servers' do
    it 'should allow to set DNS servers' do
      subject.dns_servers = %w(212.82.226.212 204.152.184.76)
      expect(subject.dns_servers).to eq ["212.82.226.212", "204.152.184.76"]
    end

    it 'should default to 1.1.1.1, 8.8.8.8 and 9.9.9.10' do
      expect(subject.dns_servers).to eq ["1.1.1.1", "8.8.8.8", "9.9.9.10"]
    end
  end

  describe 'ubuntu_mirror' do
    it 'should allow to set Ubuntu mirror server' do
      subject.ubuntu_mirror = 'http://de.archive.ubuntu.com/ubuntu/'
      expect(subject.ubuntu_mirror).to eq 'http://de.archive.ubuntu.com/ubuntu/'
    end

    it 'should default to "http://archive.ubuntu.com/ubuntu/"' do
      expect(subject.ubuntu_mirror).to eq 'http://archive.ubuntu.com/ubuntu/'
    end
  end

  describe 'ubuntu_deb_src' do
    it 'should allow to disable Ubuntu source packages' do
      subject.ubuntu_deb_src = false
      expect(subject.ubuntu_deb_src).to eq false
    end

    it 'should default to true' do
      expect(subject.ubuntu_deb_src).to eq true
    end
  end

  describe 'ubuntu_version' do
    it 'should allow to set Ubuntu version' do
      subject.ubuntu_version = '18.10'
      expect(subject.ubuntu_version).to eq '18.10'
    end

    it 'should default to 18.04.5' do
      expect(subject.ubuntu_version).to eq '18.04.5'
    end
  end

  describe 'ubuntu_major_version' do
    it 'should get major of set Ubuntu version for minor release' do
      subject.ubuntu_version = '16.04.7'
      expect(subject.ubuntu_major_version).to eq '16.04'
    end

    it 'should get major of set Ubuntu version for major release' do
      subject.ubuntu_version = '19.10'
      expect(subject.ubuntu_major_version).to eq '19.10'
    end

    it 'should default to 18.04' do
      expect(subject.ubuntu_major_version).to eq '18.04'
    end
  end

  describe 'ubuntu_name' do
    it 'should allow to set Ubuntu version nickname' do
      subject.ubuntu_name = 'Cosmic Cuttlefish'
      expect(subject.ubuntu_name).to eq 'Cosmic Cuttlefish'
    end

    it 'should default to Bionic Beaver' do
      expect(subject.ubuntu_name).to eq 'Bionic Beaver'
    end
  end

  describe 'ubuntu_kernel_flavour' do
    it 'should allow to set Ubuntu version' do
      subject.ubuntu_kernel_flavour = 'generic'
      expect(subject.ubuntu_kernel_flavour).to eq 'generic'
    end

    it 'should default to 18.04' do
      expect(subject.ubuntu_kernel_flavour).to eq 'generic-hwe-18.04'
    end
  end

  describe 'admin_email' do
    it 'should allow to set email of admin for notifications and external services like certificate generation' do
      subject.admin_email = 'admin@example.com'
      expect(subject.admin_email).to eq 'admin@example.com'
    end
  end

  describe 'email_domain' do
    it 'should allow to set email domain for outgoing mails' do
      subject.email_domain = 'mail.example.com'
      expect(subject.email_domain).to eq 'mail.example.com'
    end
  end

  describe 'host_mac_address_prefix_init' do
    it 'should allow to set MAC address prefix for virtual networks on hosts' do
      subject.host_mac_address_prefix_init = '42:23'
      expect(subject.host_mac_address_prefix_init).to eq '42:23'
    end

    it 'should default to 00:00' do
      expect(subject.host_mac_address_prefix_init).to eq '00:00'
    end
  end

  describe 'monitoring_notifiers' do
    it 'should allow to set notifiers to be called on new issues' do
      notifier = CloudModel::Notifiers::SlackNotifier.new(push_url: 'https://hooks.slack.com/services/ABC/DEF/1233cc2')
      subject.monitoring_notifiers = [
        {
          severity: [:warning, :critical, :fatal],
          notifier: notifier
        }
      ]
      expect(subject.monitoring_notifiers).to eq [
        {
          severity: [:warning, :critical, :fatal],
          notifier: notifier
        }
      ]
    end

    it 'should default to empty array' do
      expect(subject.monitoring_notifiers).to eq []
    end
  end
end