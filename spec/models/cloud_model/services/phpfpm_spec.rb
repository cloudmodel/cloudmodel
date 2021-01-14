# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Phpfpm do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 9000 }
  it { expect(subject).to have_field(:php_components).of_type(Array).with_default_value_of [] }

  describe 'kind' do
    it 'should return :phpfpm' do
      expect(subject.kind).to eq :phpfpm
    end
  end

  describe 'php_components=' do
    it 'should set php_components' do
      subject.php_components = ['php_mysql', 'php_imagemagick']
      expect(subject.php_components).to eq [:php_mysql, :php_imagemagick]
    end

    it 'should ignore unavailable components' do
      subject.php_components = ['php_virus', 'php_mysql']
      expect(subject.php_components).to eq [:php_mysql]
    end

    it 'should ignore empty components' do
      subject.php_components = ['', 'php_imagemagick']
      expect(subject.php_components).to eq [:php_imagemagick]
    end

    it 'should allow to set no components' do
      subject.php_components = ['']
      expect(subject.php_components).to eq []
    end
  end

  describe 'components_needed' do
    it 'should require php component by default' do
      expect(subject.components_needed).to eq [:php]
    end

    it 'should require php components' do
      subject.php_components = ['php_imap']
      expect(subject.components_needed).to eq [:php, :php_imap]
    end
  end

  describe 'available_php_components' do
    it 'should return list of php module components' do
      expect(subject.available_php_components).to eq [:php_mysql, :php_imagemagick, :php_imap]
    end
  end

  describe 'service_status' do
    pending
  end
end