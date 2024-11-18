require 'spec_helper'

describe "cloud_model/host/etc/systemd/system/guest_zpool_service", type: :view do
  it 'should init guests ZFS pool' do
    host = Factory.build :host, private_network_attributes: {ip: '10.42.23.1', subnet: 25}

    render template: subject, locals: {
      guests_init_string: "mirror sda7 sdb7", host: host
    }

    expect(rendered).to eq <<~SERIVCE
    [Unit]
    Description=Bootstrap zfs pool for guests
    After=network.target lxd.service lxd.socket
    Conflicts=shutdown.target

    [Service]
    Type=oneshot

    # Try to create guests pool; exists with error code if already exist
    ExecStartPre=-/sbin/zpool create guests mirror sda7 sdb7
    # Try to force mount guests pool; exists with error if already mounted
    ExecStartPre=-/sbin/zpool import -f guests

    # Init lxd if zpool create did not exit with error code aka create success
    ExecStartPre=-/usr/bin/lxd init --auto --storage-backend zfs --storage-pool default

    ExecStartPre=-/usr/bin/lxc network create lxdbr0 ipv6.address=none ipv4.address=10.42.23.1/25 ipv4.nat=true

    ExecStart=/bin/echo 'done'

    [Install]
    WantedBy=basic.target
    SERIVCE
  end

  it 'should init multiple ZFS pools' do
    host = Factory.build :host, private_network_attributes: {ip: '10.23.42.129', subnet: 25}, extra_zpools_attributes: [{name: "data", init_string: "mirror sda sdb"}]

    render template: subject, locals: {
      guests_init_string: "mirror nvme11n1p7 nvme02n1p7",
      host: host
    }

    expect(rendered).to eq <<~SERIVCE
    [Unit]
    Description=Bootstrap zfs pool for guests
    After=network.target lxd.service lxd.socket
    Conflicts=shutdown.target

    [Service]
    Type=oneshot

    # Try to create guests pool; exists with error code if already exist
    ExecStartPre=-/sbin/zpool create guests mirror nvme11n1p7 nvme02n1p7
    # Try to force mount guests pool; exists with error if already mounted
    ExecStartPre=-/sbin/zpool import -f guests

    # Try to create data pool; exists with error code if already exist
    ExecStartPre=-/sbin/zpool create data mirror sda sdb
    # Try to force mount data pool; exists with error if already mounted
    ExecStartPre=-/sbin/zpool import -f data

    # Init lxd if zpool create did not exit with error code aka create success
    ExecStartPre=-/usr/bin/lxd init --auto --storage-backend zfs --storage-pool default

    ExecStartPre=-/usr/bin/lxc storage create data zfs source=data

    ExecStartPre=-/usr/bin/lxc network create lxdbr0 ipv6.address=none ipv4.address=10.23.42.129/25 ipv4.nat=true

    ExecStart=/bin/echo 'done'

    [Install]
    WantedBy=basic.target
    SERIVCE
  end

  it 'should not allow evil strings' do
    host = Factory.build :host, private_network_attributes: {ip: '10.23.42.129', subnet: 25}, extra_zpools_attributes: [{name: "data; killall httpd", init_string: "mirror|killall sshd& sda sdb"}]

    render template: subject, locals: {
      guests_init_string: "mirror; rm -rf /usr;",
      host: host
    }

    expect(rendered).to eq <<~SERIVCE
    [Unit]
    Description=Bootstrap zfs pool for guests
    After=network.target lxd.service lxd.socket
    Conflicts=shutdown.target

    [Service]
    Type=oneshot

    # Try to create guests pool; exists with error code if already exist
    ExecStartPre=-/sbin/zpool create guests mirror\\\; rm -rf /usr\\\;
    # Try to force mount guests pool; exists with error if already mounted
    ExecStartPre=-/sbin/zpool import -f guests

    # Try to create data\\\;\\\ killall\\\ httpd pool; exists with error code if already exist
    ExecStartPre=-/sbin/zpool create data\\\;\\\ killall\\\ httpd mirror\\\|killall sshd\\\& sda sdb
    # Try to force mount data\\\;\\\ killall\\\ httpd pool; exists with error if already mounted
    ExecStartPre=-/sbin/zpool import -f data\\\;\\\ killall\\\ httpd

    # Init lxd if zpool create did not exit with error code aka create success
    ExecStartPre=-/usr/bin/lxd init --auto --storage-backend zfs --storage-pool default

    ExecStartPre=-/usr/bin/lxc storage create data\\\;\\\ killall\\\ httpd zfs source=data\\\;\\\ killall\\\ httpd

    ExecStartPre=-/usr/bin/lxc network create lxdbr0 ipv6.address=none ipv4.address=10.23.42.129/25 ipv4.nat=true

    ExecStart=/bin/echo 'done'

    [Install]
    WantedBy=basic.target
    SERIVCE
  end
end