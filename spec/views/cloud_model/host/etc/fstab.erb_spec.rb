require 'spec_helper'

describe "cloud_model/host/etc/fstab", type: :view do
  it 'should render fstab with given swap disks' do
    render template: subject, locals: {
      swap_disks: ['sda2', 'sdb2', 'nvme0n1p2']
    }
    expect(rendered).to eq <<~FSTAB
      # /etc/fstab: static file system information.
      #
      # noatime turns off atimes for increased performance (atimes normally aren't
      # needed); notail increases performance of ReiserFS (at the expense of storage
      # efficiency).  It's safe to drop the noatime options if you want and to
      # switch between notail / tail freely.
      #
      # The root filesystem should have a pass number of either 0 or 1.
      # All other filesystems should have a pass number of 0 or greater than 1.
      #
      # See the manpage fstab(5) for more information.
      #

      # <fs>      <mountpoint>  <type>    <opts>    <dump/pass>

      # NOTE: If your BOOT partition is ReiserFS, add the notail option to opts.
      /dev/md0                /boot           ext2            noauto,noatime      0 0
      /dev/md2                /               ext4            noatime             0 0
      /dev/md1                /cloud          ext4            noatime             0 0
      /dev/md4                /var/lib/lxd    ext4            noatime             0 0
      # Snap LXD needs to be mounted on another location:
      # /dev/md4                /var/snap/lxd/common/lxd    ext4            noatime             0 0
      /dev/sda2               swap            swap            defaults            0 0
      /dev/sdb2               swap            swap            defaults            0 0
      /dev/nvme0n1p2          swap            swap            defaults            0 0

      proc                    /proc           proc            defaults            0 0
      sysfs                   /sys            sysfs           noauto              0 0
      usbfs                   /proc/bus/usb   usbfs           noauto              0 0
      devpts                  /dev/pts        devpts          mode=0620,gid=5     0 0

      # glibc 2.2 and above expects tmpfs to be mounted at /dev/shm for
      # POSIX shared memory (shm_open, shm_unlink).
      # (tmpfs is a dynamically expandable/shrinkable ramdisk, and will
      #  use almost no memory if not populated with files)
      shm                     /dev/shm        tmpfs           nodev,nosuid,noexec 0 0
    FSTAB
  end
end