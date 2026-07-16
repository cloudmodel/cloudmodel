require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/nginx/server_d/passenger_conf', type: :view do
  let(:model) do
    CloudModel::Services::Nginx.new(
      passenger_env: 'production',
    )
  end

  it 'renders the default location block' do
    render template: 'cloud_model/guest/etc/nginx/server_d/passenger_conf', locals: { model: model }

    expect(rendered).to include <<~CONF
    location / {
      root                              /var/www/rails/current/public;
      passenger_base_uri                /;
      passenger_app_root                /var/www/rails/current;
      passenger_document_root           /var/www/rails/current/public;
      passenger_enabled                 on;
      passenger_min_instances           3;
      passenger_env_var                 HTTP_X_FORWARDED_PROTO $scheme;
      passenger_app_env                 production;
      passenger_preload_bundler         on;

      location ~ ^/assets/ {
        expires                         max;
        add_header                      Cache-Control public;
        access_log                      off;
      }
    }
    CONF
  end

  it 'renders custom base location' do
    allow(model).to receive(:www_root).and_return '/home/www/app_beta'

    render template: 'cloud_model/guest/etc/nginx/server_d/passenger_conf', locals: { location: '/custom/', model: model }

    expect(rendered).to include <<~CONF
      location /custom/ {
        root                              /home/www/app_beta/current/public;
        passenger_base_uri                /custom/;
        passenger_app_root                /home/www/app_beta/current;
        passenger_document_root           /home/www/app_beta/current/public;
    CONF
  end

  it "renders location overwrites inside rails base uri" do
    # Example outside base uri; should not appear
    model.location_overwrites.new(
      location: '/backend/store_stats/',
      overwrites: {
        proxy_pass: 'http://storage-backend:1234/'
      }
    )
    # Examples inside, should be included
    model.location_overwrites.new(
      location: '/api/v42/uploads/',
      overwrites: {
        client_max_body_size: '10GB'
      }
    )
    model.location_overwrites.new(
      location: '/api/v42/downloads/',
      overwrites: {
        add_header: 'Cache-Control public',
        expires: 'max'
      }
    )

    render template: 'cloud_model/guest/etc/nginx/server_d/passenger_conf', locals: { location: '/api/', model: model }

    expect(rendered).to include(
    <<~CONF
    location /api/ {
      root                              /var/www/rails/current/public;
      passenger_base_uri                /api/;
      passenger_app_root                /var/www/rails/current;
      passenger_document_root           /var/www/rails/current/public;
      passenger_enabled                 on;
      passenger_min_instances           3;
      passenger_env_var                 HTTP_X_FORWARDED_PROTO $scheme;
      passenger_app_env                 production;
      passenger_preload_bundler         on;

      location ~ ^/assets/ {
        expires                         max;
        add_header                      Cache-Control public;
        access_log                      off;
      }

      location ~ ^/api/v42/uploads/ {
        client_max_body_size            10GB;
      }

      location ~ ^/api/v42/downloads/ {
        add_header                      Cache-Control public;
        expires                         max;
      }
    }
    CONF
    )
  end
  it 'renders the ActionCable location when rails_cable_supported' do
    model.rails_cable_supported = true
    allow(model).to receive(:guest).and_return(CloudModel::Guest.new(name: 'app01'))

    render template: 'cloud_model/guest/etc/nginx/server_d/passenger_conf', locals: { model: model }

    expect(rendered).to include "  location /cable {\n" \
      "    passenger_app_group_name        app01_cable;\n" \
      "    passenger_force_max_concurrent_requests_per_process 0;\n" \
      "  }\n"
  end

  it 'renders no cable location by default' do
    render template: 'cloud_model/guest/etc/nginx/server_d/passenger_conf', locals: { model: model }

    expect(rendered).not_to include '/cable'
  end

  it 'pins the Chromium path when the web image uses the puppeteer component' do
    allow(model).to receive(:deploy_web_image).and_return(
      CloudModel::WebImage.new(additional_components: %w[puppeteer imagemagick]))

    render template: 'cloud_model/guest/etc/nginx/server_d/passenger_conf', locals: { model: model }

    expect(rendered).to include 'passenger_env_var                 PUPPETEER_EXECUTABLE_PATH /usr/bin/chromium;'
  end

  it 'omits the Chromium path without the puppeteer component' do
    allow(model).to receive(:deploy_web_image).and_return(
      CloudModel::WebImage.new(additional_components: %w[imagemagick]))

    render template: 'cloud_model/guest/etc/nginx/server_d/passenger_conf', locals: { model: model }

    expect(rendered).not_to include 'PUPPETEER_EXECUTABLE_PATH'
  end

end
