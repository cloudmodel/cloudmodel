# encoding: UTF-8

require 'spec_helper'

describe 'CloudModel#call_rake' do
  it 'should call rake with system' do
    Rails.stub(:root).and_return '/path/to/rails'  
    # stubbing on system on Kernel (stub it on the Module itself)
    CloudModel.should_receive(:system).with('bundle exec rake rspec FOCUS=\'true\' RAILS_ENV=\'test\' --trace >>/path/to/rails/log/test-rake.log 2>&1 &').and_return ''
    CloudModel::call_rake 'rspec', focus: 'true'
  end
  
  it 'should call rake with path to bundler in production' do
    Rails.stub(:root).and_return '/path/to/rails'
    Rails.stub(:env).and_return(double Object, test?: false, development?: false, to_s: 'production')
    # stubbing on system on Kernel (stub it on the Module itself)
    CloudModel.should_receive(:system).with('PATH=/bin:/sbin:/usr/bin /usr/local/bin/bundle exec rake rspec RAILS_ENV=\'production\' --trace >>/path/to/rails/log/production-rake.log 2>&1 &').and_return ''
    CloudModel::call_rake 'rspec'
  end
  
  it 'should escape parameter strings' do
    Rails.stub(:root).and_return '/path/to/rails'  
    Rails.stub(:env).and_return(double Object, test?: true, development?: false, to_s: 'test;rm -rf /;')
    # stubbing on system on Kernel (stub it on the Module itself)
    CloudModel.should_receive(:system).with('bundle exec rake rspec\\;mkfs\\ /dev/sda\\; FOCUS\\;KILLALL\\ INITD\\;=\'true\\;halt\\;\' RAILS_ENV=\'test\\;rm\\ -rf\\ /\\;\' --trace >>/path/to/rails/log/test\\;rm\\ -rf\\ /\\;-rake.log 2>&1 &').and_return ''
    CloudModel::call_rake 'rspec;mkfs /dev/sda;', :'focus;killall initd;' => 'true;halt;'
  end
end