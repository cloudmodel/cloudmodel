require 'spec_helper'

describe CloudModel::WebLocation do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:location).of_type(String).with_default_value_of('/') }

  it { expect(subject).to belong_to(:web_app).of_type(CloudModel::WebApp) }
  it { expect(subject).to be_embedded_in(:service).of_type(CloudModel::Services::Nginx) }

  describe '.location_with_slashes' do
    it 'should leave location with slashes untouched' do
      subject.location = '/abc/'
      expect(subject.location_with_slashes).to eq '/abc/'
    end

    it 'should prepend slash if none given' do
      subject.location = 'abc/xyz1/'
      expect(subject.location_with_slashes).to eq '/abc/xyz1/'
    end

    it 'should append slash if none given' do
      subject.location = '/abc/xyz2'
      expect(subject.location_with_slashes).to eq '/abc/xyz2/'
    end

    it 'should wrap slashes if none given' do
      subject.location = 'abc/xyz3'
      expect(subject.location_with_slashes).to eq '/abc/xyz3/'
    end

    it 'should pass root location' do
      subject.location = '/'
      expect(subject.location_with_slashes).to eq '/'
    end

    it 'should make root location from empty string' do
      subject.location = ''
      expect(subject.location_with_slashes).to eq '/'
    end
  end

  describe '.location_with_leading_slash' do
    it 'should leave location with slashes untouched' do
      subject.location = '/abc'
      expect(subject.location_with_leading_slash).to eq '/abc'
    end

    it 'should prepend slash if none given' do
      subject.location = 'abc/xyz1'
      expect(subject.location_with_leading_slash).to eq '/abc/xyz1'
    end

    it 'should remove trailing slash if given' do
      subject.location = '/abc/xyz2/'
      expect(subject.location_with_leading_slash).to eq '/abc/xyz2'
    end

    it 'should add leading slashes if none given' do
      subject.location = 'abc/xyz3'
      expect(subject.location_with_leading_slash).to eq '/abc/xyz3'
    end

    it 'should pass root location' do
      subject.location = '/'
      expect(subject.location_with_leading_slash).to eq '/'
    end

    it 'should make root location from empty string' do
      subject.location = ''
      expect(subject.location_with_leading_slash).to eq '/'
    end
  end
end