require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/nginx/server_d/cap-deployed_conf', type: :view do
  let(:model) { CloudModel::Services::Nginx.new capistrano_supported: true }

  def render_conf
    render template: 'cloud_model/guest/etc/nginx/server_d/cap-deployed_conf', locals: { guest: CloudModel::Guest.new, model: model }
  end

  it 'serves the deployed public directory with HTML and XML directory indexes' do
    render_conf

    expect(rendered).to match(%r{^\s*root /var/www/rails/current/public;$})
    expect(rendered).to match(/^\s*index index\.html index\.htm index\.xml;$/)
  end

  it 'answers unknown paths with /index.html by default (single-page apps)' do
    render_conf

    expect(rendered).to match(%r{^\s*try_files \$uri \$uri/ /index\.html;$})
    expect(rendered).not_to include 'error_page'
  end

  it 'answers unknown paths with a 404 and the site\'s own error pages without the fallback' do
    model.static_spa_fallback = false
    model.static_error_page_prefixes = ['de', 'fr/ca']
    render_conf

    expect(rendered).not_to include '/index.html;'
    expect(rendered.scan(%r{^\s*try_files \$uri \$uri/ =404;$}).size).to eq 3
    expect(rendered).to match(%r{location / \{.*?error_page 404 /404\.html;.*?\}}m)
    expect(rendered).to match(%r{location /de/ \{.*?error_page 404 /de/404\.html;.*?\}}m)
    expect(rendered).to match(%r{location /fr/ca/ \{.*?error_page 404 /fr/ca/404\.html;.*?\}}m)
  end

  it 'ignores the prefixes while the fallback is on' do
    model.static_error_page_prefixes = ['de']
    render_conf

    expect(rendered).not_to include 'location /de/'
  end
end
