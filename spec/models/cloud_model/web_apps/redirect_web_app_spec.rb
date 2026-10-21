require 'spec_helper'

describe CloudModel::WebApps::RedirectWebApp do
  subject { described_class.new name: 'Old Site', target_url: 'https://www.example.com' }

  it { expect(subject).to be_a CloudModel::WebApp }
  it { is_expected.to have_field(:target_url).of_type(String) }
  it { is_expected.to have_field(:root_url).of_type(String).with_default_value_of('') }
  it { is_expected.to have_field(:status).of_type(Integer).with_default_value_of(301) }
  it { is_expected.to have_field(:normalize_html).of_type(Mongoid::Boolean).with_default_value_of(false) }
  it { is_expected.to have_field(:path_mapping).of_type(Array).with_default_value_of([]) }

  it 'is registered as a web app type' do
    expect(CloudModel::WebApp.registered_apps).to include described_class
  end

  it 'needs no components' do
    expect(subject.needed_components).to eq []
  end

  describe 'validation' do
    it 'accepts a plain redirect' do
      expect(subject).to be_valid
    end

    it 'requires a target url' do
      subject.target_url = ''
      expect(subject).not_to be_valid
      expect(subject.errors[:target_url]).to be_present
    end

    it 'refuses urls that would break out of the nginx directive' do
      ['https://www.example.com/; root /;', 'ftp://example.com', 'https://example.com/$uri', "https://example.com/a\nb"].each do |url|
        subject.target_url = url
        expect(subject).not_to be_valid, "#{url.inspect} accepted"
      end
    end

    it 'allows a port and a path in the target url' do
      subject.target_url = 'http://example.com:8080/blog/'
      expect(subject).to be_valid
    end

    it 'allows a blank root url and checks a given one' do
      subject.root_url = ''
      expect(subject).to be_valid
      subject.root_url = 'https://www.example.com/start/'
      expect(subject).to be_valid
      subject.root_url = 'https://www.example.com/start/"'
      expect(subject).not_to be_valid
    end

    it 'allows only redirect status codes' do
      subject.status = 200
      expect(subject).not_to be_valid
      subject.status = 308
      expect(subject).to be_valid
    end

    it 'requires mapped paths to be paths' do
      subject.path_mapping = [['/old/', '/new/'], ['old', '/new/']]
      expect(subject).not_to be_valid
      expect(subject.errors[:path_mapping_text]).to be_present
      subject.path_mapping = [['/old/', '/new/'], ['/other.html', '/else/']]
      expect(subject).to be_valid
    end
  end

  describe '#path_mapping_text' do
    it 'round-trips one pair per line and skips blanks and comments' do
      subject.path_mapping_text = "# moved posts\n/old/  /new/\n\n/other.html /else/\n"
      expect(subject.path_mapping).to eq [['/old/', '/new/'], ['/other.html', '/else/']]
      expect(subject.path_mapping_text).to eq "/old/ /new/\n/other.html /else/"
    end

    it 'keeps a line without a target as an invalid pair' do
      subject.path_mapping_text = '/old/'
      expect(subject.path_mapping).to eq [['/old/', '']]
      expect(subject).not_to be_valid
    end
  end

  describe '#target_expression' do
    it 'appends the raw request uri without path handling' do
      expect(subject.target_expression).to eq 'https://www.example.com$request_uri'
    end

    it 'drops a trailing slash of the target url' do
      subject.target_url = 'https://www.example.com/blog/'
      expect(subject.target_expression).to eq 'https://www.example.com/blog$request_uri'
    end

    it 'uses the mapped path plus query string with path handling' do
      subject.normalize_html = true
      expect(subject.target_expression).to eq "https://www.example.com$redirect_#{subject.id}_path$is_args$args"
    end
  end

  describe '#config_files_to_render' do
    it 'renders nothing without path handling' do
      expect(subject.config_files_to_render).to eq({})
    end

    it 'renders the map into conf.d, named after the app' do
      subject.name = 'Old Site (blog)'
      subject.path_mapping = [['/a/', '/b/']]
      expect(subject.config_files_to_render).to eq(
        'cloud_model/web_apps/redirect_web_app/map.conf' => ['/etc/nginx/conf.d/redirect-old_site_blog_.conf', 0644]
      )
    end
  end

  it 'has per-app nginx variable names' do
    expect(subject.map_variable).to eq "$redirect_#{subject.id}_path"
    expect(subject.normalized_variable).to eq "$redirect_#{subject.id}_normalized"
    expect(subject.capture_prefix).to eq "redirect_#{subject.id}"
  end
end
