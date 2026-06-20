# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::RustComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "rust"' do
      expect(subject.base_name).to eq 'rust'
    end

    it 'should return "rust" if version is set' do
      subject.version = "1.95"
      expect(subject.base_name).to eq 'rust'
    end
  end

  describe 'name' do
    it 'should return :rust' do
      expect(subject.name).to eq :rust
    end

    it 'should return :rust@1.95 if version is set to 1.95' do
      subject.version = "1.95"
      expect(subject.name).to eq :'rust@1.95'
    end
  end

  describe 'human_name' do
    it 'should return "Rust"' do
      expect(subject.human_name).to eq "Rust"
    end

    it 'should return "Rust 1.95" if version is set to 1.95' do
      subject.version = "1.95"
      expect(subject.human_name).to eq "Rust 1.95"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::RustComponentWorker

      expect(CloudModel::Workers::Components::RustComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should require clang' do
      expect(subject.requirements).to eq [:clang]
    end
  end
end
