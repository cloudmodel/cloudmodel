# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::TemplateWorker do
  let(:host) { Factory :host }
  subject { CloudModel::Workers::TemplateWorker.new host }

  context '#download_path' do
    it 'should point to download path' do
      expect(subject.download_path).to eq "/cloud/build/downloads/"
    end
  end

  context '#error_log_object' do
    it 'should log errors on template' do
      template = double 'Template'
      subject.instance_variable_set :@template, template
      expect(subject.error_log_object).to eq template
    end
  end

  context '#ubuntu_version' do
    it 'should be 18.04.5 by default' do
      expect(subject.ubuntu_version).to eq '18.04.5'
    end

    it 'should be configured verion' do
      CloudModel.config.ubuntu_version = '42.04'
      expect(subject.ubuntu_version).to eq '42.04'
    end
  end

  context '#ubuntu_kernel_flavour' do
    it 'should be generic-hwe-18.04 by default' do
      expect(subject.ubuntu_kernel_flavour).to eq 'generic-hwe-18.04'
    end

    it 'should be configured kernel flavour' do
      CloudModel.config.ubuntu_kernel_flavour = 'generic-hwe-42.04'
      expect(subject.ubuntu_kernel_flavour).to eq 'generic-hwe-42.04'
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
      CloudModel.config.ubuntu_version = '42.04.5'
      allow(subject).to receive(:ubuntu_arch).and_return 'MOS6502'
      expect(subject.ubuntu_image).to eq 'ubuntu-base-42.04.5-base-MOS6502.tar.gz'
    end
  end

  pending
end