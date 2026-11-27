module CloudModel
  module Mixins
    # Database services whose server comes in distributions and release
    # lines (MongoDB, MySQL): which of them exist for the guest's OS and the
    # host's architecture ({ComponentPlatforms}), as one choice
    # (`"<distribution>:<line>"`) for forms, and a validation that rejects a
    # combination the vendor does not publish.
    #
    # The validation only runs when the choice is made or changed (a new
    # service, another distribution or line, another guest OS), so guests
    # running a combination from before the table stay editable.
    #
    # Including classes define `server_distribution_field`,
    # `server_version_field` and `component_for(distribution)`.
    module ServerPlatform
      extend ActiveSupport::Concern

      included do
        validate :server_platform_must_be_published, if: :server_platform_changed?
      end

      # @return [String, nil] OS version of the guest
      def platform_os_version
        guest&.os_version
      end

      # @return [String, nil] architecture of the guest's host
      def platform_arch
        guest&.host&.arch
      end

      # Distribution/line pairs published for the guest's OS and arch; a
      # stored service keeps its current pair in the list (so a form never
      # drops it), a new one only gets what is published.
      # @return [Array<Array(String, String)>] e.g. `[["percona", "8.0"]]`
      def available_servers
        pairs = self.class::DISTRIBUTIONS.flat_map do |distribution|
          lines = ComponentPlatforms.lines(component_for(distribution), platform_os_version, platform_arch)
          lines ||= self.class.default_lines(distribution)
          lines.map { |line| [distribution, line] }
        end
        current = [send(self.class.server_distribution_field), server_line]
        pairs << current if persisted? && current.all?(&:present?) && !pairs.include?(current)
        pairs
      end

      # The pair a form preselects: the current one when it is on offer,
      # otherwise the first published one (a new service whose defaults the
      # vendor does not publish for this guest).
      # @return [String] `"<distribution>:<line>"`
      def selected_server
        pairs = available_servers
        return server if pairs.include?([send(self.class.server_distribution_field), server_line]) || pairs.empty?
        pairs.first.join(':')
      end

      # @return [String] `"<distribution>:<line>"`
      def server
        "#{send(self.class.server_distribution_field)}:#{server_line}"
      end

      # @param value [String] `"<distribution>:<line>"`
      def server= value
        distribution, line = value.to_s.split(':', 2)
        send "#{self.class.server_distribution_field}=", distribution if distribution.present?
        send "#{self.class.server_version_field}=", line if line.present?
      end

      # @return [String, nil] the release line this service runs on
      def server_line
        send(self.class.server_version_field)
      end

      private

      def server_platform_changed?
        new_record? ||
          send("#{self.class.server_distribution_field}_changed?") ||
          send("#{self.class.server_version_field}_changed?") ||
          guest&.os_version_changed?
      end

      def server_platform_must_be_published
        distribution = send(self.class.server_distribution_field)
        return unless self.class::DISTRIBUTIONS.include?(distribution)
        supported = ComponentPlatforms.supported?(component_for(distribution), server_line, platform_os_version, platform_arch)
        return unless supported == false

        alternatives = available_servers.reject { |pair| pair == [distribution, server_line] }.map { |d, l| "#{d} #{l}" }
        errors.add self.class.server_version_field, :not_published,
          component: component_for(distribution), version: server_line, os: platform_os_version, arch: platform_arch,
          alternatives: alternatives.any? ? alternatives.join(', ') : '-'
      end
    end
  end
end
