require 'rubygems/package'

module CloudModel
  # A non-host device (laptop, CI runner, developer machine) that connects to
  # the tinc VPN overlay network.
  #
  # VpnClient records store the device's tinc public key and static VPN address.
  # The {#config_tarball} method generates a ready-to-extract tinc configuration
  # archive for the device, including host key files for every managed host.
  class VpnClient
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] name
    #   @return [String] unique device name (lowercase, alphanumeric + hyphens/underscores)
    field :name, type: String

    # @!attribute [rw] tinc_public_key
    #   @return [String] RSA public key for this device (PEM format)
    field :tinc_public_key, type: String

    # @!attribute [rw] address
    #   @return [String] static IPv4 address assigned to this device on the VPN
    field :address, type: String

    # @!attribute [rw] os
    #   @return [String, nil] operating system label (informational)
    field :os, type: String

    validates :name, presence: true, uniqueness: true, format: {with: /\A[a-z0-9\-_]+\z/}
    validates :tinc_public_key, presence: true
    validates :address, presence: true, format: /\A((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.)){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/


    # Generates a tar archive containing a complete tinc configuration for this device.
    #
    # The archive includes `tinc.conf`, `tinc-up`, `tinc-down` scripts, and a
    # `hosts/` directory with keys for this client and every managed host.
    # Extract it into `/etc/tinc/<network_name>/` on the client device.
    #
    # @return [StringIO] an in-memory tar stream
    def config_tarball
      tarfile = StringIO.new("")
      data_mode = 0640
      exec_mode = 0750

      Gem::Package::TarWriter.new(tarfile) do |tar|
        tar.add_file "tinc.conf", data_mode do |tf|
          tf.write ActionController::Base.new.render_to_string(template: "/cloud_model/vpn_clients/tinc_conf", locals: {vpn_client: self})
        end

        tar.add_file "tinc-up", exec_mode do |tf|
          tf.write ActionController::Base.new.render_to_string(template: "/cloud_model/vpn_clients/tinc-up", locals: {vpn_client: self})
        end

        tar.add_file "tinc-down", exec_mode do |tf|
          tf.write ActionController::Base.new.render_to_string(template: "/cloud_model/vpn_clients/tinc-down", locals: {vpn_client: self})
        end

        tar.mkdir 'hosts', exec_mode

        tar.add_file "hosts/#{name.downcase.gsub('-', '_')}", data_mode do |tf|
          tf.write ActionController::Base.new.render_to_string(template: "/cloud_model/vpn_clients/client", locals: {vpn_client: self})
        end

        CloudModel::Host.each do |host|
          unless host.tinc_public_key.blank?
            tar.add_file "hosts/#{host.name.downcase.gsub('-', '_')}", data_mode do |tf|
              tf.write ActionController::Base.new.render_to_string(template: "/cloud_model/host/etc/tinc/host", locals: {host: host})
            end
          end
        end

      end
      tarfile
    end
  end
end