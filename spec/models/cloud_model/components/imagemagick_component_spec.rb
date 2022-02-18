# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::ImagemagickComponent do
  it { expect(subject).to be_a CloudModel::Components::ImagemagickComponent }

  describe 'base_name' do
    it 'should return "imagemagick"' do
      expect(subject.base_name).to eq 'imagemagick'
    end

    it 'should return "imagemagick" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'imagemagick'
    end
  end

  describe 'name' do
    it 'should return :imagemagick' do
      expect(subject.name).to eq :imagemagick
    end

    it 'should return :imagemagick@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'imagemagick@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "ImageMagick"' do
      expect(subject.human_name).to eq "ImageMagick"
    end

    it 'should return "Imagemagick 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "ImageMagick 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      worker_class = double CloudModel::Workers::Components::ImagemagickComponentWorker

      expect(CloudModel::Workers::Components::ImagemagickComponentWorker).to receive(:new).with(host, component: subject).and_return worker_class
      expect(subject.worker host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end