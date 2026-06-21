# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::TemplateWorker do
  let(:host) { Factory :host }
  subject { CloudModel::Workers::TemplateWorker.new host }

  context '#download_path' do
    it 'should point to download path' do
      username = Faker::Internet.username
      allow(CloudModel.config).to receive(:data_directory).and_return "/homes/#{username}/www/admin/data"
      expect(subject.download_path).to eq "/homes/#{username}/www/admin/data/build/downloads/"
    end
  end

  context '#error_log_object' do
    it 'should log errors on template' do
      template = double 'Template'
      subject.instance_variable_set :@template, template
      expect(subject.error_log_object).to eq template
    end
  end

  context '#os_version' do
    it 'should get os version from template' do
      template = double 'Template', os_version: 'basic-2.0'
      subject.instance_variable_set :@template, template
      expect(subject.os_version).to eq 'basic-2.0'
    end
  end

  context '#ubuntu_version' do
    it 'should get ubuntu version from template (deprecated)' do
      template = double 'Template', os_version: 'ubuntu-18.04.5'
      subject.instance_variable_set :@template, template
      expect(subject.ubuntu_version).to eq '18.04.5'
    end
  end

  context '#ubuntu_arch' do
    it 'should return arch of template' do
      template = double 'Template', arch: 'amd64'
      subject.instance_variable_set :@template, template
      expect(subject.ubuntu_arch).to eq 'amd64'
    end
  end

  context '#ubuntu_image' do
    it 'should generate ubuntu tar ball name' do
      allow(subject).to receive(:ubuntu_version).and_return '42.04.5'
      allow(subject).to receive(:ubuntu_arch).and_return 'MOS6502'
      expect(subject.ubuntu_image).to eq 'ubuntu-base-42.04.5-base-MOS6502.tar.gz'
    end
  end

  before do
    allow(subject).to receive(:comment_sub_step)
    allow(subject).to receive(:chroot!)
    allow(subject).to receive(:chroot)
    allow(subject).to receive(:mkdir_p)
    allow(subject).to receive(:render_to_remote)
    allow(subject).to receive(:build_tar)
    allow(host).to receive(:exec)
    allow(host).to receive(:exec!)
    allow(host).to receive(:sftp).and_return(double('sftp'))
  end

  context '#ubuntu_url' do
    it 'should generate release URL for stable version' do
      allow(subject).to receive(:ubuntu_version).and_return '22.04'
      allow(subject).to receive(:ubuntu_image).and_return 'ubuntu-base-22.04-base-amd64.tar.gz'
      expect(subject.ubuntu_url).to eq 'http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-amd64.tar.gz'
    end
  end

  context '#fetch_os' do
    it 'should call fetch_ubuntu and populate_root for ubuntu versions' do
      allow(subject).to receive(:os_version).and_return 'ubuntu-22.04'
      expect(subject).to receive(:fetch_ubuntu)
      expect(subject).to receive(:populate_root)
      subject.fetch_os
    end

    it 'should call debootstrap_debian for non-ubuntu versions' do
      allow(subject).to receive(:os_version).and_return 'debian-12'
      expect(subject).to receive(:debootstrap_debian)
      subject.fetch_os
    end
  end

  context '#fetch_ubuntu' do
    it 'should not download if file already exists' do
      sftp = double 'sftp'
      allow(host).to receive(:sftp).and_return(sftp)
      allow(FileUtils).to receive(:mkdir_p)
      allow(subject).to receive(:download_path).and_return('/data/build/downloads/')
      allow(subject).to receive(:ubuntu_image).and_return('ubuntu-base-22.04-base-amd64.tar.gz')
      allow(sftp).to receive(:stat!).and_return(true)
      expect(host).not_to receive(:exec!)
      subject.fetch_ubuntu
    end

    it 'should download if file does not exist' do
      sftp = double 'sftp'
      allow(host).to receive(:sftp).and_return(sftp)
      allow(FileUtils).to receive(:mkdir_p)
      allow(subject).to receive(:download_path).and_return('/data/build/downloads/')
      allow(subject).to receive(:ubuntu_image).and_return('ubuntu-base-22.04-base-amd64.tar.gz')
      allow(subject).to receive(:ubuntu_url).and_return('http://example.com/image.tar.gz')
      allow(sftp).to receive(:stat!).and_raise(RuntimeError)
      expect(host).to receive(:exec!).with(anything, "Failed to download ubuntu image")
      subject.fetch_ubuntu
    end
  end

  context '#update_base' do
    it 'should run dpkg configure and apt upgrade in chroot' do
      allow(subject).to receive(:build_path).and_return('/build')
      expect(subject).to receive(:chroot!).with('/build', "dpkg --configure -a && apt-get update && apt-get upgrade -y", "Failed to update sources")
      subject.update_base
    end
  end

  context '#install_ssh' do
    it 'should install ssh in chroot' do
      allow(subject).to receive(:build_path).and_return('/build')
      expect(subject).to receive(:chroot!).with('/build', "apt-get install ssh -y", "Failed to install SSH")
      subject.install_ssh
    end
  end

  context '#tar_template' do
    it 'should create tarball excluding tmp, run, cache, docs, and ssh keys' do
      template = double 'template', tarball: '/cloud/templates/test.tar.gz'
      expect(subject).to receive(:build_tar).with(
        '.', '/cloud/templates/test.tar.gz',
        hash_including(one_file_system: true, C: '/build')
      )
      subject.tar_template '/build', template
    end
  end

  context '#download_new_template' do
    it 'should update build_state and download template' do
      template = double 'template'
      subject.instance_variable_set :@template, template
      expect(template).to receive(:update_attribute).with(:build_state, :downloading)
      expect(subject).to receive(:download_template).with(template)
      subject.download_new_template
    end
  end

  context '#finalize_template' do
    it 'should update build_state, cleanup chroot, and remove build path' do
      template = double 'template'
      subject.instance_variable_set :@template, template
      allow(subject).to receive(:build_path).and_return('/build/test')
      expect(template).to receive(:update_attribute).with(:build_state, :finished)
      expect(subject).to receive(:cleanup_chroot).with('/build/test')
      expect(host).to receive(:exec).with("rm -rf /build/test")
      subject.finalize_template
    end
  end
end