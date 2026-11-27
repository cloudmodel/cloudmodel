module CloudModel
  module Workers
    module Components
      # Makes the server's own `/etc/mysql/mysql.cnf` the `my.cnf` of a
      # template build chroot.
      #
      # `/etc/mysql/my.cnf` is a Debian alternative. When the core template
      # holds `mariadb-common` (pulled in by `libmariadb3`), its `mariadb.cnf`
      # wins with priority 200; it includes `conf.d` and `mariadb.conf.d` only,
      # so a MySQL or Percona server would never read `mysql.conf.d` — neither
      # the package's `mysqld.cnf` nor the configuration rendered there on
      # deploy (bind address, `auth_socket`, telemetry switch).
      module MysqlConfigFile
        PATH = "/etc/mysql/mysql.cnf".freeze

        PRIORITY = 300

        # @param worker [BaseComponentWorker] worker whose chroot! runs the command
        # @param build_path [String] template chroot
        def self.select! worker, build_path
          worker.chroot! build_path, "update-alternatives --install /etc/mysql/my.cnf my.cnf #{PATH} #{PRIORITY} && test \"$(readlink -f /etc/mysql/my.cnf)\" = #{PATH}", "Failed to make #{PATH} the my.cnf"
        end
      end
    end
  end
end
