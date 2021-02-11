require 'spec_helper'

describe CloudModel::WebApps::PhpWebApp do
  it { expect(subject).to be_a CloudModel::WebApp }

  describe '.needed_components' do
    it 'should require php components' do
      expect(subject.needed_components).to eq [:php]
    end
  end
end