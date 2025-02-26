require 'spec_helper'

RSpec.describe CloudModel::Services::Nginx::LocationOverwrite, type: :model do
  describe 'fields' do
    it { is_expected.to have_field(:location).of_type(String) }
    it { is_expected.to have_field(:overwrites).of_type(Hash).with_default_value_of({}) }
  end

  describe 'validations' do
    subject { described_class.new(location: '/test') }

    it { is_expected.to validate_presence_of(:location) }
    it { is_expected.to validate_uniqueness_of(:location) }
  end

  describe 'associations' do
    it { is_expected.to be_embedded_in(:service).of_type(CloudModel::Services::Nginx) }
  end
end