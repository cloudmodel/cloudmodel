# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Collabora do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 9980 }
  it { expect(subject).to have_field(:wopi_host).of_type(String).with_default_value_of nil }

  describe 'kind' do
    it 'should return :collabora' do
      expect(subject.kind).to eq :collabora
    end
  end

  describe 'components_needed' do
    it 'should require collabora component' do
      expect(subject.components_needed).to eq [:collabora]
    end
  end

  describe 'service_status' do
    it 'should return an empty hash' do
      expect(subject.service_status).to eq({})
    end
  end
end
