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
end
