require 'spec_helper'

RSpec.describe 'cloud_model/web_apps/redirect_web_app/map_conf', type: :view do
  let(:model) do
    CloudModel::WebApps::RedirectWebApp.new(
      name: 'Old Site',
      target_url: 'https://www.example.com',
      path_mapping: [['/2015/10/old-title/', '/2015/10/30/new-title/'], ['/greetings/', '/']]
    )
  end

  it 'maps the request uri onto the redirect path' do
    render template: 'cloud_model/web_apps/redirect_web_app/map_conf', locals: { model: model }

    expect(rendered).to include <<~CONF
      map $uri $redirect_#{model.id}_path {
          default $uri;
          /2015/10/old-title/ /2015/10/30/new-title/;
          /greetings/ /;
      }
    CONF
    expect(rendered).not_to include '_normalized'
  end

  it 'normalizes html pages first when asked to' do
    model.normalize_html = true

    render template: 'cloud_model/web_apps/redirect_web_app/map_conf', locals: { model: model }

    expect(rendered).to include <<~CONF
      map $uri $redirect_#{model.id}_normalized {
          default $uri;
          ~^(?<redirect_#{model.id}_dir>.*/)index\\.html$ $redirect_#{model.id}_dir;
          ~^(?<redirect_#{model.id}_page>.*)\\.html$ $redirect_#{model.id}_page/;
      }
    CONF
    expect(rendered).to include <<~CONF
      map $redirect_#{model.id}_normalized $redirect_#{model.id}_path {
          default $redirect_#{model.id}_normalized;
          /2015/10/old-title/ /2015/10/30/new-title/;
    CONF
  end

  it 'renders an identity map for normalization without pairs' do
    model.normalize_html = true
    model.path_mapping = []

    render template: 'cloud_model/web_apps/redirect_web_app/map_conf', locals: { model: model }

    expect(rendered).to include "map $redirect_#{model.id}_normalized $redirect_#{model.id}_path {\n    default $redirect_#{model.id}_normalized;\n}\n"
  end
end
