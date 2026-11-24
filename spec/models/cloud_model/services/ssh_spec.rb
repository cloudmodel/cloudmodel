# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Ssh do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject.allow_public_service?).to eq true }
  
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 22 }
  it { expect(subject).to have_field(:authorized_keys).of_type Array }
  
  describe 'kind' do
    it 'should return :ssh' do
      expect(subject.kind).to eq :ssh
    end
  end
  
  describe 'components_needed' do
    it 'should require no components as ssh is build int ocore' do
      expect(subject.components_needed).to eq []
    end
  end
  
  describe 'service_status' do
    let(:guest) { double CloudModel::Guest, private_address: '10.42.0.1' }
    before { allow(subject).to receive(:guest).and_return(guest) }

    it 'should return ping time on success' do
      expect(Socket).to receive(:tcp).with('10.42.0.1', 22, connect_timeout: 5)

      result = subject.service_status
      expect(result).to have_key(:ping)
      expect(result[:ping]).to be_a Float
    end

    it 'should return error hash on failure' do
      expect(Socket).to receive(:tcp).with('10.42.0.1', 22, connect_timeout: 5).and_raise Errno::ETIMEDOUT

      result = subject.service_status
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :critical
    end
  end
end