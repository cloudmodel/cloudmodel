require 'spec_helper'

describe CloudModel::WebApp do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:name).of_type String }

  describe '#registered_apps' do
    it 'should list the available apps' do
      expect(subject.class.registered_apps).to eq [
        CloudModel::WebApps::StaticWebApp,
        CloudModel::WebApps::PhpWebApp,
        CloudModel::WebApps::WordpressWebApp,
        CloudModel::WebApps::RoundcubemailWebApp,
        CloudModel::WebApps::NextcloudWebApp
      ]
    end
  end

  describe '.needed_components' do
    it 'should not need any components' do
      expect(subject.needed_components).to eq []
    end
  end

  describe '.additional_allowed_params' do
    it 'should not need any additional params' do
      expect(subject.additional_allowed_params).to eq []
    end
  end

  describe '#app_name' do
    it 'should be empty String' do
      expect(subject.class.app_name).to eq ''
    end
  end

  describe '#app_folder' do
    it 'should be "/opt/web-app/"' do
      expect(subject.class.app_folder).to eq '/opt/web-app/'
    end
  end

  describe '#fetch_app_command' do
    it 'should not have an fetch command' do
      expect(subject.class.fetch_app_command).to eq false
    end
  end

  describe '.config_files_to_render' do
    it 'should not have any files to render' do
      expect(subject.config_files_to_render).to eq({})
    end
  end
end