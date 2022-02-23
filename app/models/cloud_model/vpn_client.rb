require 'rubygems/package'

module CloudModel
  class VpnClient
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    field :name, type: String
    field :tinc_public_key, type: String
    field :address, type: String
    field :os, type: String

    validates :name, presence: true, uniqueness: true, format: {with: /\A[a-z0-9\-_]+\z/}
    validates :tinc_public_key, presence: true
    validates :address, presence: true, format: /\A((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.)){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/


    def config_tarball
      tarfile = StringIO.new("")
      data_mode = 0640
      exec_mode = 0750

      Gem::Package::TarWriter.new(tarfile) do |tar|
        tar.add_file "tinc.conf", data_mode do |tf|
          tf.write ActionController::Base.new.render_to_string(template: "/cloud_model/vpn_clients/tinc.conf", locals: {vpn_client: self})
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