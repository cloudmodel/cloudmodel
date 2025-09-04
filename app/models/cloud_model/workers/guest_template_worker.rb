module CloudModel
  module Workers
    class GuestTemplateWorker < TemplateWorker

      def build_path
        if @template.is_a? CloudModel::GuestCoreTemplate
          "/cloud/build/core/#{@template.id}"
        else
          "/cloud/build/#{@template.template_type.id}/#{@template.id}"
        end
      end

      def error_log_object
        @template
      end

      def install_utils
        comment_sub_step 'Install gnupg'
        chroot! build_path, "apt-get install sudo gnupg -y", "Failed to install gnupg"

        comment_sub_step 'Install ppa support'
        chroot! build_path, "apt-get install apt-transport-https ca-certificates -y", "Failed to install ppa support"

        # Don't try to install software-properties-common on debian < 13, it is included in base template
        # chroot build_path, "apt-get install software-properties-common -y"

        comment_sub_step 'Install rsync, wget, and curl'
        chroot! build_path, "apt-get install sudo rsync wget curl -y", "Failed to install rsync, wget, and curl"

        comment_sub_step 'Install nano editor'
        chroot! build_path, "apt-get install sudo nano -y", "Failed to install nano"

        comment_sub_step 'Install msmtp mailer'
        chroot! build_path, "apt-get install sudo msmtp msmtp-mta mailutils -y", "Failed to install msmtp"

        comment_sub_step 'Configure autologin'
        # Autologin
        mkdir_p "#{build_path}/etc/systemd/system/console-getty.service.d"
        render_to_remote "/cloud_model/guest/etc/systemd/system/console-getty.service.d/autologin.conf", "#{build_path}/etc/systemd/system/console-getty.service.d/autologin.conf"

        comment_sub_step 'Apply fixterm patch'
        # Tool for setting serial console size in terminal; call on virsh console to fix terminal size
        render_to_remote "/cloud_model/guest/bin/fixterm.sh", "#{build_path}/bin/fixterm", 0755
      end

      def install_network
        comment_sub_step 'Install netbase'
        chroot! build_path, "apt-get install netbase iproute2 isc-dhcp-client -y", "Failed to install network base"
        render_to_remote "/cloud_model/guest/etc/systemd/system/dhclient.service", "#{build_path}/etc/systemd/system/dhclient.service"
        mkdir_p "#{build_path}/etc/systemd/system/multi-user.target.wants"
        #chroot! build_path, "ln -s /etc/systemd/system/dhclient.service /etc/systemd/system/multi-user.target.wants/dhclient.service", "Failed to enable dhclient service"
      end

      def install_check_mk_agent
        #chroot! build_path, "apt-get install check-mk-agent -y", "Failed to install CheckMKAgent"

        chroot! build_path, "curl -s https://raw.githubusercontent.com/Checkmk/checkmk/2.2.0/agents/check_mk_agent.linux >/usr/bin/check_mk_agent && chmod 755 /usr/bin/check_mk_agent", "Failed to install CheckMKAgent"

        render_to_remote "/cloud_model/guest/etc/systemd/system/check_mk@.service", "#{build_path}/etc/systemd/system/check_mk@.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/check_mk.socket", "#{build_path}/etc/systemd/system/check_mk.socket"
        mkdir_p "#{build_path}/etc/systemd/system/sockets.target.wants"
        chroot! build_path, "ln -s /etc/systemd/system/check_mk.socket /etc/systemd/system/sockets.target.wants/check_mk.socket", "Failed to add check_mk to autostart"

        mkdir_p "#{build_path}/usr/lib/check_mk_agent/plugins/"
        %w(cgroup_mem cgroup_cpu df_k systemd guest_load).each do |sensor|
          render_to_remote "/cloud_model/support/usr/lib/check_mk_agent/plugins/#{sensor}", "#{build_path}/usr/lib/check_mk_agent/plugins/#{sensor}", 0755
        end

        render_to_remote "/cloud_model/support/usr/sbin/cgroup_load_writer", "#{build_path}/usr/sbin/cgroup_load_writer", 0755
        render_to_remote "/cloud_model/guest/etc/systemd/system/cgroup_load_writer.service", "#{build_path}/etc/systemd/system/cgroup_load_writer.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/cgroup_load_writer.timer", "#{build_path}/etc/systemd/system/cgroup_load_writer.timer"
        chroot! build_path, "ln -s /etc/systemd/system/cgroup_load_writer.timer /etc/systemd/system/timers.target.wants/cgroup_load_writer.timer", "Failed to enable cgroup_load_writer service"
      end

      def pack_template
        @template.update_attribute :build_state, :packaging
        tar_template build_path, @template
      end

      def pack_manifest
        mkdir_p "#{build_path}/templates"
        render_to_remote "/cloud_model/guest_template/metadata.yaml", "#{build_path}/metadata.yaml", template: @template
        %w(hosts.tpl hostname.tpl).each do |file|
          render_to_remote "/cloud_model/guest_template/#{file}", "#{build_path}/templates/#{file}", template: @template
        end

        @host.exec! "cd #{build_path} && tar czvf #{@template.lxd_image_metadata_tarball} metadata.yaml templates/*", "Failed to write metadata"
      end

      def download_template template
        return if CloudModel.config.skip_sync_images

        super template

        unless template.is_a? CloudModel::GuestCoreTemplate
          # Download build template to local distribution
          tarball_target = "#{CloudModel.config.data_directory}#{template.lxd_image_metadata_tarball}"
          FileUtils.mkdir_p File.dirname(tarball_target)
          command = "scp -C -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa root@#{@host.ssh_address}:#{template.lxd_image_metadata_tarball.shellescape} #{tarball_target.shellescape}"
          Rails.logger.debug command
          local_exec! command, "Failed to download archived metadata"
        end
      end

      def upload_template template
        return if CloudModel.config.skip_sync_images

        super template

        unless template.is_a? CloudModel::GuestCoreTemplate
          # Upload build template to host
          srcball_target = "#{CloudModel.config.data_directory}#{template.lxd_image_metadata_tarball}"
          mkdir_p File.dirname(template.tarball)
          command = "scp -C -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa #{srcball_target.shellescape} root@#{@host.ssh_address}:#{template.lxd_image_metadata_tarball.shellescape}"
          Rails.logger.debug command
          local_exec! command, "Failed to upload built metadata"
        end
      end

      def build_core_template template, options={}
        unless template.build_state == :pending or options[:force]
          puts "Template not pending"
          return false
        end

        @template = template

        template.update_attributes build_state: :running, os_version: os_version

        mkdir_p build_path
        mkdir_p download_path

        steps = [
          ["Download #{os_version}", :fetch_os],
          ["Update base system", :update_base],
          ["Install basic utils", :install_utils],
          ["Install network utils", :install_network],
          ["Install SSH server", :install_ssh],
          ["Install check_mk agent for monitoring", :install_check_mk_agent],
          ["Pack template tarball", :pack_template],
          ["Download template tarball", :download_new_template],
          ["Finalize", :finalize_template]
        ]


        if options[:prepend_output]
          puts options[:prepend_output]
        end

        begin
          run_steps :build, steps, options
        rescue Exception => e
          CloudModel.log_exception e
          template.update_attributes build_state: :failed, build_last_issue: "#{e}"
          puts "#{e.class}: #{e.message}"
          e.backtrace.each do |bt|
            puts "\tfrom #{bt}"
          end
          cleanup_chroot build_path
          raise "Failed to build core image!"
        end

        template.update_attributes build_state: :finished, build_last_issue: ""

        return template
      end

      #---

      def fetch_core_template
        if @template.core_template.blank?
          @template.core_template = CloudModel::GuestCoreTemplate.create! arch: @host.arch, os_version: @template.os_version
          @template.core_template.build! @host
        end

        begin
          @host.sftp.stat!("#{@template.core_template.tarball}")
        rescue
          comment_sub_step "Downloading core template"
          upload_template @template.core_template
        end
        @host.exec! "cd #{build_path} && tar xzpf #{@template.core_template.tarball.shellescape}", "Failed to unpack core template"
        # Copy resolv.conf
        @host.exec! "rm #{build_path}/etc/resolv.conf", "Failed to remove old resolve conf"
        @host.exec! "cp /etc/resolv.conf #{build_path}/etc", "Failed to copy resolve conf"
      end

      def install_components
        @template.template_type.components.each do |component_type|
          begin
            c = CloudModel::Components::BaseComponent.from_sym(component_type)
            comment_sub_step "Install #{c.human_name}"
            component = c.worker @template, @host
          rescue Exception => e
            CloudModel.log_exception e
            raise "Component :#{component_type} has no worker"
          end
          component.build build_path
        end
      end

      def build_template(template, options={})
        return false unless template.build_state == :pending or options[:force]

        @template = template

        template.update_attributes build_state: :running

        mkdir_p build_path
        mkdir_p download_path

        steps = [
          ["Download Core Template #{@template.core_template.try(:id)} (#{@template.created_at})", :fetch_core_template],
          ["Install Components", :install_components],
          ["Pack template tarball", :pack_template],
          ["Create lxd manifest", :pack_manifest],
          ["Download template tarball", :download_new_template],
          ["Finalize", :finalize_template]
        ]


        if options[:prepend_output]
          puts options[:prepend_output]
        end

        begin
          run_steps :build, steps, options
        rescue Exception => e
          CloudModel.log_exception e
          template.update_attributes build_state: :failed, build_last_issue: "#{e}"
          puts "#{e.class}: #{e.message}"
          e.backtrace.each do |bt|
            puts "\tfrom #{bt}"
          end
          cleanup_chroot build_path
          raise "Failed to build core image!"
        end

        template.update_attributes build_state: :finished, build_last_issue: ""

        return template
        #----

        begin


          template.template_type.components.each do |component_type|
            begin
              component_const = "CloudModel::Components::#{component_type.to_s.gsub(/[^a-z0-9]*/, '').camelcase}ComponentWorker".constantize
              component = component_const.new @host
            rescue Exception => e
              CloudModel.log_exception e
              raise "Component :#{component_type} has no worker"
            end
            component.build build_path
          end

          puts '    Packaging'
          template.update_attribute :build_state, :packaging
          pack_template build_path, template

          puts '    Downloading'
          template.update_attribute :build_state, :downloading
          download_template template

          template.update_attribute :build_state, :finished
        rescue Exception => e
          CloudModel.log_exception e
          template.update_attributes build_state: :failed, build_last_issue: "#{e}"
          cleanup_chroot build_path
          raise "Failed to build core image!"
        end

        puts "    Cleanup"
        cleanup_chroot build_path
        @host.exec "rm -rf #{build_path.shellescape}"

        return template
      end
    end
  end
end