module CloudModel
  module Workers
    module Components
      # Component worker that installs Percona Server for MySQL into a guest
      # template chroot, from Percona's apt repository of the release series
      # (see {PerconaRepository}).
      class PerconaServerComponentWorker < BaseComponentWorker
        # Release series installed when the component carries no version.
        PERCONA_SERIES = "8.4".freeze

        def series
          @options[:component].try(:version).presence || PERCONA_SERIES
        end

        # Repository name of the series: the LTS series are published as
        # `ps-<major><minor>-lts`, 8.0 as `ps-80`.
        def repository
          self.class.repository_for series
        end

        # @param series [String] e.g. `"8.4"`
        # @return [String] Percona repository of the series
        def self.repository_for series
          short = series.delete('.')
          series == '8.0' ? "ps-#{short}" : "ps-#{short}-lts"
        end

        def build build_path
          PerconaRepository.add! self, build_path, @template, [repository]
          chroot! build_path, "DEBIAN_FRONTEND=noninteractive apt-get install percona-server-server -y", "Failed to install Percona Server #{series}"
        end
      end
    end
  end
end
