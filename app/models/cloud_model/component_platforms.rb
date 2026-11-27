require 'net/http'
require 'zlib'

module CloudModel
  # Which release line of a server component exists for which guest OS and
  # architecture. The vendors do not publish every line for every
  # distribution (MongoDB has no server for Debian 13, MySQL and Fleet no
  # arm64 builds, Percona no arm64 MongoDB for Debian 12 …), and a template
  # build for a missing combination fails late, deep in `apt-get install`.
  #
  # The table lives in `config/component_platforms.yml` of the engine and is
  # checked against the vendors' apt indexes by
  # `rake cloudmodel:components:platforms` (prints the differences; WRITE=1
  # writes the file). Services validate their choice against it and forms
  # offer only what it allows.
  #
  # A component or OS the table does not know is not restricted (nil from
  # {.supported?}): the table narrows what is known to be missing, it does
  # not forbid what nobody checked.
  module ComponentPlatforms
    FILE = File.expand_path('../../../config/component_platforms.yml', __dir__).freeze

    # Guest OS versions and architectures the table covers.
    OS_VERSIONS = %w(debian-12 debian-13 ubuntu-18.04 ubuntu-22.04 ubuntu-24.04).freeze
    ARCHES = %w(amd64 arm64).freeze

    # Release lines checked per component and, per component, where its
    # package index is and which package must be in it.
    PROBES = {
      'mongodb' => {
        # major releases only (see CloudModel.mongodb_version_path)
        lines: %w(4.4 5.0 6.0 7.0 8.0 9.0),
        package: 'mongodb-org-server',
        index: ->(line, os, codename, arch) {
          os == 'ubuntu' ?
            "https://repo.mongodb.org/apt/ubuntu/dists/#{codename}/mongodb-org/#{line}/multiverse/binary-#{arch}/Packages.gz" :
            "https://repo.mongodb.org/apt/debian/dists/#{codename}/mongodb-org/#{line}/main/binary-#{arch}/Packages.gz"
        }
      },
      'percona_server_mongodb' => {
        # major releases only; 9.0 appears once Percona publishes it
        lines: %w(6.0 7.0 8.0 9.0),
        package: 'percona-server-mongodb-server',
        index: ->(line, _os, codename, arch) {
          "https://repo.percona.com/#{Workers::Components::PerconaServerMongodbComponentWorker.repository_for line}/apt/dists/#{codename}/main/binary-#{arch}/Packages"
        }
      },
      'percona_server' => {
        lines: %w(8.0 8.4),
        package: 'percona-server-server',
        index: ->(line, _os, codename, arch) {
          "https://repo.percona.com/#{Workers::Components::PerconaServerComponentWorker.repository_for line}/apt/dists/#{codename}/main/binary-#{arch}/Packages"
        }
      },
      'mysql' => {
        lines: %w(8.0 8.4),
        package: 'mysql-community-server',
        index: ->(line, os, codename, arch) {
          "https://repo.mysql.com/apt/#{os}/dists/#{codename}/#{Workers::Components::MysqlComponentWorker.repository_for line}/binary-#{arch}/Packages"
        }
      }
    }.freeze

    # @return [Hash] component => line => os_version => [arch]
    def self.table
      @table ||= File.exist?(FILE) ? (YAML.safe_load(File.read(FILE)) || {}) : {}
    end

    def self.reload!
      @table = nil
      table
    end

    # The table's key for an OS version ("ubuntu-22.04.4" → "ubuntu-22.04").
    # @return [String, nil]
    def self.os_key os_version
      OS_VERSIONS.find { |k| os_version.to_s == k || os_version.to_s.start_with?("#{k}.") }
    end

    # @return [Boolean, nil] true/false when the table knows the component
    #   and the OS, nil otherwise
    def self.supported? component, line, os_version, arch
      lines = table[component.to_s]
      os = os_key(os_version)
      return nil if lines.nil? || os.nil? || arch.blank?
      Array(lines.dig(line.to_s, os)).include?(arch.to_s)
    end

    # @return [Array<String>, nil] the lines of the component available for
    #   the OS and arch (oldest first), nil when the table does not know them
    def self.lines component, os_version, arch
      lines = table[component.to_s]
      os = os_key(os_version)
      return nil if lines.nil? || os.nil? || arch.blank?
      lines.select { |_line, oses| Array(oses[os]).include?(arch.to_s) }.keys
    end

    # Reads the vendors' package indexes.
    # @return [Hash] in the shape of {.table}
    def self.probe log: nil
      PROBES.to_h do |component, probe|
        lines = probe[:lines].to_h do |line|
          oses = OS_VERSIONS.to_h do |os_version|
            os = os_version.split('-').first
            codename = CloudModel.debian_short_name(os_version)
            arches = ARCHES.select do |arch|
              url = probe[:index].call(line, os, codename, arch)
              found = index_has_package?(url, probe[:package])
              log&.call "#{component} #{line} #{os_version} #{arch}: #{found ? 'yes' : '-'}"
              found
            end
            [os_version, arches]
          end
          [line, oses.reject { |_os, arches| arches.empty? }]
        end
        [component, lines.reject { |_line, oses| oses.empty? }]
      end
    end

    # @return [Boolean] whether the (optionally gzipped) apt index at url
    #   lists the package
    def self.index_has_package? url, package
      response = Net::HTTP.get_response(URI(url))
      return false unless response.is_a?(Net::HTTPSuccess)
      body = response.body.to_s
      body = Zlib.gunzip(body) if url.end_with?('.gz')
      body.each_line.any? { |l| l.chomp == "Package: #{package}" }
    rescue StandardError
      false
    end

    # @return [String] YAML of a probed table with a header
    def self.to_yaml table
      "# Release lines per guest OS and arch, from the vendors' apt indexes.\n" \
      "# Checked by `rake cloudmodel:components:platforms` (WRITE=1 rewrites it)\n" \
      "# on #{Date.today.iso8601}.\n" + table.to_yaml.sub(/\A---\n/, '')
    end
  end
end
