module CloudModel
  module Workers
    module Components
      # Adds Percona's signed apt repositories to a template build chroot.
      #
      # The Percona packaging key is fetched by fingerprint from the Ubuntu
      # keyserver (it is not on keys.openpgp.org) and the build fails unless
      # the keyring holds exactly that primary key; apt then checks every
      # package against it. Percona's server packages depend on
      # `percona-telemetry-agent`, which lives in the separate `telemetry`
      # repository, so that one is always added as well. Whether telemetry is
      # sent is a deploy-time decision of the service (see
      # {Services::PerconaTelemetry}), the template is the same either way.
      module PerconaRepository
        # Fingerprint of the Percona packaging key the repositories are signed with.
        KEY = "4D1BB29D63D98E422B2113B19334A25F8507EFA5".freeze

        KEYSERVER = "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x".freeze

        KEYRING = "/usr/share/keyrings/percona-keyring.gpg".freeze

        # @param worker [BaseComponentWorker] worker whose chroot! runs the commands
        # @param build_path [String] template chroot
        # @param template [CloudModel::GuestTemplate] for the distribution codename
        # @param repositories [Array<String>] Percona repositories, e.g. `["ps-84-lts"]`
        def self.add! worker, build_path, template, repositories
          worker.chroot! build_path, "apt-get install curl ca-certificates gnupg -y", "Failed to install key management"

          worker.chroot! build_path, "curl -fsSL #{"#{KEYSERVER}#{KEY}".shellescape} | gpg --batch --no-tty --dearmor > #{KEYRING}", "Failed to fetch Percona repository key"
          worker.chroot! build_path, "test \"$(gpg --batch --no-tty --show-keys --with-colons #{KEYRING} | awk -F: '$1 == \"pub\" { getline; print $10 }')\" = #{KEY}", "Percona repository keyring does not hold exactly the key #{KEY}"
          worker.chroot build_path, "gpgconf --kill all"

          codename = CloudModel.debian_short_name(template.os_version)
          (repositories + ['telemetry']).uniq.each do |repo|
            worker.chroot! build_path, "echo #{"deb [signed-by=#{KEYRING}] http://repo.percona.com/#{repo}/apt #{codename} main".shellescape} > /etc/apt/sources.list.d/percona-#{repo}.list", "Failed to add Percona #{repo} repository"
          end

          worker.chroot! build_path, "apt-get update", "Failed to update packages"
        end
      end
    end
  end
end
