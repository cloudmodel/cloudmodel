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

    # Init lxd if zpool create did not exit with error code aka create success.
    # --storage-pool names the ZFS pool to use (the LXD pool is always created
    # as "default") — it must reference the guests zpool created above, else
    # lxd init tries to conjure a zpool "default" and fails, leaving LXD
    # without any storage pool while the network create below still succeeds.
    ExecStartPre=-/usr/bin/lxd init --auto --storage-backend zfs --storage-pool guests

    ExecStartPre=-/usr/bin/lxc network create lxdbr0 ipv6.address=none ipv4.address=10.42.23.1/25 ipv4.nat=true
    # lxd init above creates lxdbr0 itself with a RANDOM subnet, making the
    # create a silent no-op — force the intended config either way.
    ExecStartPre=-/usr/bin/lxc network set lxdbr0 ipv4.address 10.42.23.1/25
    ExecStartPre=-/usr/bin/lxc network set lxdbr0 ipv4.nat true
    ExecStartPre=-/usr/bin/lxc network set lxdbr0 ipv6.address none

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

    # Init lxd if zpool create did not exit with error code aka create success.
    # --storage-pool names the ZFS pool to use (the LXD pool is always created
    # as "default") — it must reference the guests zpool created above, else
    # lxd init tries to conjure a zpool "default" and fails, leaving LXD
    # without any storage pool while the network create below still succeeds.
    ExecStartPre=-/usr/bin/lxd init --auto --storage-backend zfs --storage-pool guests

    ExecStartPre=-/usr/bin/lxc storage create data zfs source=data

    ExecStartPre=-/usr/bin/lxc network create lxdbr0 ipv6.address=none ipv4.address=10.23.42.129/25 ipv4.nat=true
    # lxd init above creates lxdbr0 itself with a RANDOM subnet, making the
    # create a silent no-op — force the intended config either way.
    ExecStartPre=-/usr/bin/lxc network set lxdbr0 ipv4.address 10.23.42.129/25
    ExecStartPre=-/usr/bin/lxc network set lxdbr0 ipv4.nat true
    ExecStartPre=-/usr/bin/lxc network set lxdbr0 ipv6.address none

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

    # Init lxd if zpool create did not exit with error code aka create success.
    # --storage-pool names the ZFS pool to use (the LXD pool is always created
    # as "default") — it must reference the guests zpool created above, else
    # lxd init tries to conjure a zpool "default" and fails, leaving LXD
    # without any storage pool while the network create below still succeeds.
    ExecStartPre=-/usr/bin/lxd init --auto --storage-backend zfs --storage-pool guests

    ExecStartPre=-/usr/bin/lxc storage create data\\\;\\\ killall\\\ httpd zfs source=data\\\;\\\ killall\\\ httpd

    ExecStartPre=-/usr/bin/lxc network create lxdbr0 ipv6.address=none ipv4.address=10.23.42.129/25 ipv4.nat=true
    # lxd init above creates lxdbr0 itself with a RANDOM subnet, making the
    # create a silent no-op — force the intended config either way.
    ExecStartPre=-/usr/bin/lxc network set lxdbr0 ipv4.address 10.23.42.129/25
    ExecStartPre=-/usr/bin/lxc network set lxdbr0 ipv4.nat true
    ExecStartPre=-/usr/bin/lxc network set lxdbr0 ipv6.address none

    ExecStart=/bin/echo 'done'

    [Install]
    WantedBy=basic.target
    SERIVCE
  end
end