# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::LibfcgiComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'name' do
    it 'should return :libfcgi' do
      expect(subject.name).to eq :libfcgi
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end