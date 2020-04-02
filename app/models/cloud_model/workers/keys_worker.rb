require 'fileutils'
require 'net/http'
require 'net/sftp'
require 'securerandom'

module CloudModel
  module Workers
    class KeysWorker < BaseWorker
      def initialize
        @host = CloudModel::MockHost.new
        @hosts = CloudModel::Host.all
      end
    
      def add_new_ssh_key(host)
        host.exec("/bin/echo #{@new_public_key.shellescape} >> /root/.ssh/authorized_keys")
      end
    
      def remove_old_ssh_key(host)
        host.exec("/bin/echo #{@new_public_key.shellescape} > /root/.ssh/authorized_keys")
      end
    
      def create_ssh_priv_key
        key_dir = "#{CloudModel.config.data_directory.shellescape}/new_keys"
        local_exec! "rm -rf #{key_dir}", "Failed remove new key dir"
        local_exec! "mkdir -p #{key_dir}", "Failed to create new key dir"
        local_exec "ssh-keygen -N '' -t rsa -b 4096 -f #{key_dir}/id_rsa"
      end
    
      def update_ssh_priv_key
        if File.exists? "#{CloudModel.config.data_directory.shellescape}/keys"
          File.rename "#{CloudModel.config.data_directory.shellescape}/keys", "#{CloudModel.config.data_directory.shellescape}/keys_#{Time.now}"
        end
        File.rename "#{CloudModel.config.data_directory.shellescape}/new_keys", "#{CloudModel.config.data_directory.shellescape}/keys"
      end
    
      def read_ssh_pub_key
        @new_public_key = File.read("#{CloudModel.config.data_directory.shellescape}/new_keys/id_rsa.pub").strip
      end
    
      def config_sshd(host)
        mock_host = @host
        begin
          @host = host
          render_to_remote "/cloud_model/host/etc/ssh/sshd_config", "/etc/ssh/sshd_config"
        ensure
          @host = mock_host
        end
        host.exec! "systemctl reload sshd", "Failed to reload SSHd"
      end
    
      # def renew_tinc_key(host)
      # end
      #
      # def sync_tinc_hosts(host)
      # end
      #
      # def restart_tincd(host)
      # end
    
      def renew options = {}
        build_start_at = Time.now
      
        steps = [
          ['Exchange SSH root keys', [
            ['Generate new key', :create_ssh_priv_key],
            ['Read public key', :read_ssh_pub_key, on_skip: :read_ssh_pub_key],
            ['Add new key to accept keys on', :add_new_ssh_key, each: @hosts],
            ['Change to use new key', :update_ssh_priv_key],
            ['Remove old key from ssh accept keys on', :remove_old_ssh_key, each: @hosts],
            ['config_sshd', :config_sshd, each: @hosts]
          ]],
          # ['Exchange Tinc keys', [
          #   ['Renew private key for', :renew_tinc_key, each: @hosts],
          #   ['Write new host files on', :sync_tinc_hosts, each: @hosts],
          #   ['Restart tincd on', :restart_tincd, each: @hosts]
          # ]],
        ]
      
        run_steps :deploy, steps, options
      
        puts "Finished renew keys in #{distance_of_time_in_words_to_now build_start_at}"      
      end
    end
  end
end