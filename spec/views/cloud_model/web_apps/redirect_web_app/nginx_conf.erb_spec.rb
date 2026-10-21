require 'spec_helper'

RSpec.describe 'cloud_model/web_apps/redirect_web_app/nginx_conf', type: :view do
  let(:app) { CloudModel::WebApps::RedirectWebApp.new name: 'Old Site', target_url: 'https://www.example.com/' }
  let(:model) { CloudModel::WebLocation.new location: '/', web_app: app }

  it 'redirects everything with the raw request uri' do
    render template: 'cloud_model/web_apps/redirect_web_app/nginx_conf', locals: { model: model }

    expect(rendered).to include <<~CONF
      location / {
        return 301 https://www.example.com$request_uri;
      }
    CONF
    expect(rendered).not_to include 'location = /'
  end

  it 'sends the location itself to the root url' do
    app.root_url = 'https://www.example.com/start/'
    app.status = 302

    render template: 'cloud_model/web_apps/redirect_web_app/nginx_conf', locals: { model: model }

    expect(rendered).to include <<~CONF
      location / {
        location = / {
          return 302 https://www.example.com/start/;
        }

        return 302 https://www.example.com$request_uri;
      }
    CONF
  end

  it 'uses the mapped path with the query string when paths are handled' do
    app.normalize_html = true

    render template: 'cloud_model/web_apps/redirect_web_app/nginx_conf', locals: { model: model }

    expect(rendered).to include "  return 301 https://www.example.com$redirect_#{app.id}_path$is_args$args;\n"
  end

  it 'renders a sub location' do
    model.location = '/archive'

    render template: 'cloud_model/web_apps/redirect_web_app/nginx_conf', locals: { model: model }

    expect(rendered).to include "location /archive {\n"
  end
end
