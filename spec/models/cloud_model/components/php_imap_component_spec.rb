# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::PhpImapComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'name' do
    it 'should return :php_imap' do
      expect(subject.name).to eq :php_imap
    end
  end

  describe 'requirements' do
    it 'should require php' do
      expect(subject.requirements).to eq [:php]
    end
  end
end