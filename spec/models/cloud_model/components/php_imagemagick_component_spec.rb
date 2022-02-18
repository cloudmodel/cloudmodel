# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::PhpImagemagickComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "php_imagemagick"' do
      expect(subject.base_name).to eq 'php_imagemagick'
    end

    it 'should return "php_imagemagick" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'php_imagemagick'
    end
  end

  describe 'name' do
    it 'should return :php_imagemagick' do
      expect(subject.name).to eq :php_imagemagick
    end

    it 'should return :php_imagemagick@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'php_imagemagick@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "PHP ImageMagick"' do
      expect(subject.human_name).to eq "PHP ImageMagick"
    end

    it 'should return "PHP ImageMagick 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "PHP ImageMagick 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      worker_class = double CloudModel::Workers::Components::PhpImagemagickComponentWorker

      expect(CloudModel::Workers::Components::PhpImagemagickComponentWorker).to receive(:new).with(host, component: subject).and_return worker_class
      expect(subject.worker host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should require imagemagick and php' do
      expect(subject.requirements).to eq [:imagemagick, :php]
    end
  end
end