require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/nginx/htpasswd', type: :view do
  let(:model) { CloudModel::Services::Nginx.new basic_auth_supported: true }

  it 'renders the logins unescaped, one per line' do
    a = model.basic_auth_users.build name: 'demo', password: 'opensesame'
    b = model.basic_auth_users.build name: 'review', password: 'x&y<z'

    render template: 'cloud_model/guest/etc/nginx/htpasswd', locals: { model: model }

    expect(rendered).to eq "demo:#{a.password_hash}\nreview:#{b.password_hash}\n"
  end
end
