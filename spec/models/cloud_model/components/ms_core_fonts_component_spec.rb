# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::MsCoreFontsComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "ms_core_fonts"' do
      expect(subject.base_name).to eq 'ms_core_fonts'
    end
  end

  describe 'name' do
    it 'should return :ms_core_fonts' do
      expect(subject.name).to eq :ms_core_fonts
    end

    it 'should return :ms_core_fonts@1 if version is set to 1' do
      subject.version = "1"
      expect(subject.name).to eq :'ms_core_fonts@1'
    end
  end

  describe 'human_name' do
    it 'should return "MsCoreFonts"' do
      expect(subject.human_name).to eq "MsCoreFonts"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::MsCoreFontsComponentWorker

      expect(CloudModel::Workers::Components::MsCoreFontsComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end
