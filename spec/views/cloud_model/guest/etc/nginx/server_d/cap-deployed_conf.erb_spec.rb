require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/nginx/server_d/cap-deployed_conf', type: :view do
  it 'serves the deployed public directory with HTML and XML directory indexes' do
    render template: 'cloud_model/guest/etc/nginx/server_d/cap-deployed_conf', locals: { guest: CloudModel::Guest.new, model: CloudModel::Services::Nginx.new }

    expect(rendered).to match(%r{^\s*root /var/www/rails/current/public;$})
    expect(rendered).to match(/^\s*index index\.html index\.htm index\.xml;$/)
  end
end
