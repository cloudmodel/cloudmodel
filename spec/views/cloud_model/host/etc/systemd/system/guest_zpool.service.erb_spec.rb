require 'spec_helper'

describe "cloud_model/host/etc/systemd/system/guest_zpool.service", type: :view do
  it 'should init ZFS pool' do
    render template: subject, locals: {
      zpools: {
        default: "mirror sda7 sdb7"
      }
    }
    expect(rendered).to eq <<~SERIVCE
    [Unit]
    Description=Bootstrap zfs pool for guests
    Before=network.target lxd.service lxd.socket
    Conflicts=shutdown.target

    [Service]
    Type=oneshot
    # Try to create guests pool; exists with error code if already exist
    ExecStartPre=-/sbin/zpool create default mirror sda7 sdb7
    # Try to force mount guests pool; exists with error if already mounted
    ExecStartPre=-/sbin/zpool import -f default

    # Init lxd if zpool create did not exit with error code aka create success
    ExecStartPre=-/usr/bin/lxd init --auto --storage-backend zfs --storage-pool default
    ExecStart=/bin/echo 'done'

    [Install]
    WantedBy=basic.target
    SERIVCE
  end

  it 'should init multiple ZFS pools' do
    render template: subject, locals: {
      zpools: {
        default: "mirror nvme11n1p7 nvme02n1p7",
        data: "mirror sda sdb"
      }
    }
    expect(rendered).to eq <<~SERIVCE
    [Unit]
    Description=Bootstrap zfs pool for guests
    Before=network.target lxd.service lxd.socket
    Conflicts=shutdown.target

    [Service]
    Type=oneshot
    # Try to create guests pool; exists with error code if already exist
    ExecStartPre=-/sbin/zpool create default mirror nvme11n1p7 nvme02n1p7
    # Try to force mount guests pool; exists with error if already mounted
    ExecStartPre=-/sbin/zpool import -f default

    # Try to create guests pool; exists with error code if already exist
    ExecStartPre=-/sbin/zpool create data mirror sda sdb
    # Try to force mount guests pool; exists with error if already mounted
    ExecStartPre=-/sbin/zpool import -f data

    # Init lxd if zpool create did not exit with error code aka create success
    ExecStartPre=-/usr/bin/lxd init --auto --storage-backend zfs --storage-pool default
    ExecStart=/bin/echo 'done'

    [Install]
    WantedBy=basic.target
    SERIVCE
  end

  it 'should not allow evil strings' do
    render template: subject, locals: {
      zpools: {
        default: "mirror; rm -rf /usr;",
        data: "mirror|killall sshd& sda sdb"
      }
    }
    expect(rendered).to eq <<~SERIVCE
    [Unit]
    Description=Bootstrap zfs pool for guests
    Before=network.target lxd.service lxd.socket
    Conflicts=shutdown.target

    [Service]
    Type=oneshot
    # Try to create guests pool; exists with error code if already exist
    ExecStartPre=-/sbin/zpool create default mirror\\\; rm -rf /usr\\\;
    # Try to force mount guests pool; exists with error if already mounted
    ExecStartPre=-/sbin/zpool import -f default

    # Try to create guests pool; exists with error code if already exist
    ExecStartPre=-/sbin/zpool create data mirror\\\|killall sshd\\\& sda sdb
    # Try to force mount guests pool; exists with error if already mounted
    ExecStartPre=-/sbin/zpool import -f data

    # Init lxd if zpool create did not exit with error code aka create success
    ExecStartPre=-/usr/bin/lxd init --auto --storage-backend zfs --storage-pool default
    ExecStart=/bin/echo 'done'

    [Install]
    WantedBy=basic.target
    SERIVCE
  end
end