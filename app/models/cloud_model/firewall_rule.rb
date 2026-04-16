module CloudModel
  # An iptables/nftables port-forwarding rule embedded in a {Host}.
  #
  # Each rule maps an incoming source IP and port to a target IP and port using
  # a specified protocol. The {Workers::FirewallWorker} renders these rules into
  # firewall start/stop scripts on the host.
  class FirewallRule
    require 'resolv'
    require 'securerandom'

    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::AcceptSizeStrings
    include CloudModel::Mixins::ENumFields
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] host
    #   @return [CloudModel::Host] the host this rule belongs to
    embedded_in :host, class_name: "CloudModel::Host", inverse_of: :firewall_rules

    # @!attribute [rw] source_ip
    #   @return [String] source IP or CIDR range to match (e.g. `"0.0.0.0/0"` for any)
    field :source_ip, type: String

    # @!attribute [rw] source_port
    #   @return [Integer] source port to match
    field :source_port, type: Integer

    # @!attribute [rw] target_ip
    #   @return [String] destination IP address to forward traffic to
    field :target_ip, type: String

    # @!attribute [rw] target_port
    #   @return [Integer] destination port to forward traffic to
    field :target_port, type: Integer

    # @!attribute [rw] service_kind
    #   @return [String] optional label for the kind of service (default: `"generic"`)
    field :service_kind, type: String, default: 'generic'

    # @!attribute [rw] protocol
    #   @return [String] `"tcp"` or `"udp"` (default: `"tcp"`)
    field :protocol, type: String, default: 'tcp'

    validates :source_ip, presence: true
    validates :source_port, presence: true
    validates :target_ip, presence: true
    validates :target_port, presence: true
    validates :protocol, inclusion: { in: %w[tcp udp] }

    # Returns a human-readable summary of the rule.
    # @return [String] e.g. `"0.0.0.0/0:443->10.42.1.10:443"`
    def name
      "#{source_ip}:#{source_port}->#{target_ip}:#{target_port}"
    end
  end
end