module CloudModel
  class FirewallRule
    require 'resolv'
    require 'securerandom'

    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::AcceptSizeStrings
    include CloudModel::Mixins::ENumFields
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    embedded_in :host, class_name: "CloudModel::Host", inverse_of: :firewall_rules

    field :source_ip, type: String
    field :source_port, type: Integer
    field :target_ip, type: String
    field :target_port, type: Integer
    field :service_kind, type: String, default: 'generic'
    field :protocol, type: String, default: 'tcp'

    validates :source_ip, presence: true
    validates :source_port, presence: true
    validates :target_ip, presence: true
    validates :target_port, presence: true
    validates :protocol, inclusion: { in: %w[tcp udp] }

    def name
      "#{source_ip}:#{source_port}->#{target_ip}:#{target_port}"
    end
  end
end