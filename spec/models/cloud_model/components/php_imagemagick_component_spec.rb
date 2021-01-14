# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::PhpImagemagickComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'name' do
    it 'should return :php_imagemagick' do
      expect(subject.name).to eq :php_imagemagick
    end
  end

  describe 'requirements' do
    it 'should require imagemagick and php' do
      expect(subject.requirements).to eq [:imagemagick, :php]
    end
  end
end