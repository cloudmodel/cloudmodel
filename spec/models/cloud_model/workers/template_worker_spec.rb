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

  pending
end