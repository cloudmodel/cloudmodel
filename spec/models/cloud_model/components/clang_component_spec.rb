# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::ClangComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "clang"' do
      expect(subject.base_name).to eq 'clang'
    end
  end

  describe 'name' do
    it 'should return :clang' do
      expect(subject.name).to eq :clang
    end

    it 'should return :clang@16 if version is set to 16' do
      subject.version = "16"
      expect(subject.name).to eq :'clang@16'
    end
  end

  describe 'human_name' do
    it 'should return "Clang/LLVM"' do
      expect(subject.human_name).to eq "Clang/LLVM"
    end

    it 'should return "Clang/LLVM 16" if version is set to 16' do
      subject.version = "16"
      expect(subject.human_name).to eq "Clang/LLVM 16"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::ClangComponentWorker

      expect(CloudModel::Workers::Components::ClangComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end
