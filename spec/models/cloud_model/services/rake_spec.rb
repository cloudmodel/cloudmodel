# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Rake do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:rake_task).of_type String }
  it { expect(subject).to have_field(:rake_timer_accuracy_sec).of_type(Integer).with_default_value_of 600 }
  it { expect(subject).to have_field(:rake_timer_on_calendar).of_type(Mongoid::Boolean).with_default_value_of true }
  it { expect(subject).to have_field(:rake_timer_on_calendar_val).of_type(String).with_default_value_of '00:00' }
  it { expect(subject).to have_field(:rake_timer_persistent).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:rake_timer_on_boot).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:rake_timer_on_boot_sec).of_type(Integer).with_default_value_of 900 }

  describe 'kind' do
    it 'should return :headless' do
      expect(subject.kind).to eq :headless
    end
  end

  describe 'components_needed' do
    it 'should require nginx component' do
      expect(subject.components_needed).to eq [:nginx]
    end
  end

  describe 'service_status' do
    it 'should return false' do
      expect(subject.service_status).to eq false
    end
  end
end