# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::RubyComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::RubyComponentWorker.new host}
  
  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }
  
  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end
    
    it 'should apt-get ruby' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install ruby git zlib1g-dev libxml2-dev ruby-bcrypt nodejs imagemagick libxml2-utils libxslt-dev -y', 'Failed to install packages for deployment of rails app')
      expect(subject).to receive(:chroot!).with('/tmp/build', 'gem install bundler', 'Failed to install bundler')
      
      subject.build '/tmp/build'
    end
  end
end