module CloudModel
  module Workers
    module Services
      # Switches the Percona telemetry agent of a guest on or off at deploy
      # time. The agent is a hard dependency of Percona's server packages, so
      # it is always installed (see {Components::PerconaRepository}); it only
      # runs when the service's telemetry switch is on, otherwise its unit is
      # masked. The servers' own telemetry is switched in their config files.
      module PerconaTelemetry
        # @param enabled [Boolean]
        def write_percona_telemetry_agent enabled
          systemd = "#{@guest.deploy_path.shellescape}/etc/systemd/system"
          wants = "#{systemd}/multi-user.target.wants/percona-telemetry-agent.service"
          mask = "#{systemd}/percona-telemetry-agent.service"
          if enabled
            @host.exec! "rm -f #{mask} && ln -sf /lib/systemd/system/percona-telemetry-agent.service #{wants}", "Failed to enable percona telemetry agent"
          else
            @host.exec! "rm -f #{wants} && ln -sf /dev/null #{mask}", "Failed to mask percona telemetry agent"
          end
        end
      end
    end
  end
end
