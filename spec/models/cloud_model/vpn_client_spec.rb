# encoding: UTF-8

require 'spec_helper'

describe CloudModel::VpnClient do
  it { expect(subject).to have_timestamps }
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:tinc_public_key).of_type String }
  it { expect(subject).to have_field(:address).of_type String }
  it { expect(subject).to have_field(:os).of_type String }

  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name) }
  it { expect(subject).to validate_format_of(:name).to_allow("host-name-01") }
  it { expect(subject).to validate_format_of(:name).not_to_allow("Test Host") }
  it { expect(subject).to validate_presence_of(:tinc_public_key) }
  it { expect(subject).to validate_presence_of(:address) }
  it { expect(subject).to validate_format_of(:address).to_allow("127.0.0.1") }
  it { expect(subject).to validate_format_of(:address).not_to_allow("256.2.1.2") }

  describe 'config_tarball' do
    it 'should return a StringIO tar archive' do
      subject.name = 'test-client'
      controller = double 'controller'
      allow(ActionController::Base).to receive(:new).and_return(controller)
      allow(controller).to receive(:render_to_string).and_return('rendered content')
      allow(CloudModel::Host).to receive(:each).and_yield(double(name: 'host1', tinc_public_key: 'key'))

      result = subject.config_tarball
      expect(result).to be_a StringIO
    end
  end
end