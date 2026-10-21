require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/mongodb_conf', type: :view do
  it 'sets the WiredTiger cache explicitly from the guest memory' do
    guest = CloudModel::Guest.new(memory_size: 8 * 1024**3)
    model = CloudModel::Services::Mongodb.new(port: 27017)
    model.guest = guest
    render template: 'cloud_model/guest/etc/mongodb_conf', locals: { model: model, guest: guest }

    expect(rendered).to include <<~CONF
      storage:
          dbPath: "/var/lib/mongodb"
          wiredTiger:
              engineConfig:
                  cacheSizeGB: 6.0
    CONF
  end
end
