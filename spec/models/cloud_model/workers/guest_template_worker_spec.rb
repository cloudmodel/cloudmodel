# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::GuestTemplateWorker do
  let(:host) { double CloudModel::Host, arch: 'amd64', ssh_address: '10.0.0.1', sftp: double('sftp') }
  subject { CloudModel::Workers::GuestTemplateWorker.new host }

  describe 'build_path' do
    it 'should return core build path for GuestCoreTemplate' do
      template = double CloudModel::GuestCoreTemplate, id: 'core123'
      allow(template).to receive(:is_a?).with(CloudModel::GuestCoreTemplate).and_return(true)
      subject.instance_variable_set :@template, template

      expect(subject.build_path).to eq '/cloud/build/core/core123'
    end

    it 'should return template type build path for GuestTemplate' do
      template_type = double id: 'type456'
      template = double CloudModel::GuestTemplate, id: 'tmpl789', template_type: template_type
      allow(template).to receive(:is_a?).with(CloudModel::GuestCoreTemplate).and_return(false)
      subject.instance_variable_set :@template, template

      expect(subject.build_path).to eq '/cloud/build/type456/tmpl789'
    end
  end

  describe 'error_log_object' do
    it 'should return the template' do
      template = double
      subject.instance_variable_set :@template, template

      expect(subject.error_log_object).to eq template
    end
  end

  context 'with a guest template' do
    let(:template_type) { double id: 'type1', components: [:ruby, :xml] }
    let(:core_template) { double CloudModel::GuestCoreTemplate, tarball: '/cloud/templates/core.tar.gz' }
    let(:template) do
      double CloudModel::GuestTemplate,
        id: 'tmpl1',
        template_type: template_type,
        core_template: core_template,
        os_version: 'ubuntu-22.04',
        created_at: Time.now,
        lxd_image_metadata_tarball: '/cloud/templates/metadata.tar.gz'
    end

    before do
      allow(template).to receive(:is_a?).with(CloudModel::GuestCoreTemplate).and_return(false)
      subject.instance_variable_set :@template, template
    end

    describe 'install_utils' do
      before do
        allow(subject).to receive(:comment_sub_step)
        allow(subject).to receive(:chroot!)
        allow(subject).to receive(:mkdir_p)
        allow(subject).to receive(:render_to_remote)
      end

      it 'should install gnupg' do
        expect(subject).to receive(:chroot!).with(subject.build_path, "apt-get install sudo gnupg -y", "Failed to install gnupg")
        subject.install_utils
      end

      it 'should install ppa support' do
        expect(subject).to receive(:chroot!).with(subject.build_path, "apt-get install apt-transport-https ca-certificates -y", "Failed to install ppa support")
        subject.install_utils
      end

      it 'should install rsync, wget, and curl' do
        expect(subject).to receive(:chroot!).with(subject.build_path, "apt-get install sudo rsync wget curl -y", "Failed to install rsync, wget, and curl")
        subject.install_utils
      end

      it 'should install nano editor' do
        expect(subject).to receive(:chroot!).with(subject.build_path, "apt-get install sudo nano -y", "Failed to install nano")
        subject.install_utils
      end

      it 'should install msmtp mailer' do
        expect(subject).to receive(:chroot!).with(subject.build_path, "apt-get install sudo msmtp msmtp-mta mailutils -y", "Failed to install msmtp")
        subject.install_utils
      end

      it 'should configure autologin' do
        expect(subject).to receive(:mkdir_p).with("#{subject.build_path}/etc/systemd/system/console-getty.service.d")
        expect(subject).to receive(:render_to_remote).with(
          "/cloud_model/guest/etc/systemd/system/console-getty.service.d/autologin.conf",
          "#{subject.build_path}/etc/systemd/system/console-getty.service.d/autologin.conf"
        )
        subject.install_utils
      end

      it 'should install fixterm script' do
        expect(subject).to receive(:render_to_remote).with(
          "/cloud_model/guest/bin/fixterm.sh",
          "#{subject.build_path}/bin/fixterm",
          0755
        )
        subject.install_utils
      end
    end

    describe 'install_network' do
      before do
        allow(subject).to receive(:comment_sub_step)
        allow(subject).to receive(:chroot!)
        allow(subject).to receive(:mkdir_p)
        allow(subject).to receive(:render_to_remote)
      end

      it 'should install netbase and networking packages' do
        expect(subject).to receive(:chroot!).with(subject.build_path, "apt-get install netbase iproute2 isc-dhcp-client -y", "Failed to install network base")
        subject.install_network
      end

      it 'should render dhclient service' do
        expect(subject).to receive(:render_to_remote).with(
          "/cloud_model/guest/etc/systemd/system/dhclient.service",
          "#{subject.build_path}/etc/systemd/system/dhclient.service"
        )
        subject.install_network
      end

      it 'should create multi-user.target.wants directory' do
        expect(subject).to receive(:mkdir_p).with("#{subject.build_path}/etc/systemd/system/multi-user.target.wants")
        subject.install_network
      end
    end

    describe 'install_check_mk_agent' do
      before do
        allow(subject).to receive(:chroot!)
        allow(subject).to receive(:mkdir_p)
        allow(subject).to receive(:render_to_remote)
      end

      it 'should install check_mk agent' do
        expect(subject).to receive(:chroot!).with(
          subject.build_path,
          "curl -s https://raw.githubusercontent.com/Checkmk/checkmk/2.2.0/agents/check_mk_agent.linux >/usr/bin/check_mk_agent && chmod 755 /usr/bin/check_mk_agent",
          "Failed to install CheckMKAgent"
        )
        subject.install_check_mk_agent
      end

      it 'should render check_mk service and socket units' do
        expect(subject).to receive(:render_to_remote).with(
          "/cloud_model/guest/etc/systemd/system/check_mk@.service",
          "#{subject.build_path}/etc/systemd/system/check_mk@.service"
        )
        expect(subject).to receive(:render_to_remote).with(
          "/cloud_model/guest/etc/systemd/system/check_mk.socket",
          "#{subject.build_path}/etc/systemd/system/check_mk.socket"
        )
        subject.install_check_mk_agent
      end

      it 'should enable check_mk socket in autostart' do
        expect(subject).to receive(:chroot!).with(
          subject.build_path,
          "ln -s /etc/systemd/system/check_mk.socket /etc/systemd/system/sockets.target.wants/check_mk.socket",
          "Failed to add check_mk to autostart"
        )
        subject.install_check_mk_agent
      end

      it 'should install monitoring plugins' do
        %w(cgroup_mem cgroup_cpu df_k systemd guest_load).each do |sensor|
          expect(subject).to receive(:render_to_remote).with(
            "/cloud_model/support/usr/lib/check_mk_agent/plugins/#{sensor}",
            "#{subject.build_path}/usr/lib/check_mk_agent/plugins/#{sensor}",
            0755
          )
        end
        subject.install_check_mk_agent
      end

      it 'should install cgroup_load_writer and its timer' do
        expect(subject).to receive(:render_to_remote).with(
          "/cloud_model/support/usr/sbin/cgroup_load_writer",
          "#{subject.build_path}/usr/sbin/cgroup_load_writer",
          0755
        )
        expect(subject).to receive(:chroot!).with(
          subject.build_path,
          "ln -s /etc/systemd/system/cgroup_load_writer.timer /etc/systemd/system/timers.target.wants/cgroup_load_writer.timer",
          "Failed to enable cgroup_load_writer service"
        )
        subject.install_check_mk_agent
      end
    end

    describe 'install_components' do
      let(:ruby_component) { double 'ruby_component', human_name: 'Ruby' }
      let(:xml_component) { double 'xml_component', human_name: 'XML' }
      let(:ruby_worker) { double 'ruby_worker' }
      let(:xml_worker) { double 'xml_worker' }

      before do
        allow(CloudModel::Components::BaseComponent).to receive(:from_sym).with(:ruby).and_return(ruby_component)
        allow(CloudModel::Components::BaseComponent).to receive(:from_sym).with(:xml).and_return(xml_component)
        allow(ruby_component).to receive(:worker).and_return(ruby_worker)
        allow(xml_component).to receive(:worker).and_return(xml_worker)
        allow(ruby_worker).to receive(:build)
        allow(xml_worker).to receive(:build)
        allow(subject).to receive(:comment_sub_step)
        allow(subject).to receive(:chroot!)
      end

      it 'should run apt-get update before installing components' do
        expect(subject).to receive(:chroot!).with(subject.build_path, "apt-get update", "Failed to update package lists").ordered
        expect(ruby_worker).to receive(:build).with(subject.build_path).ordered
        expect(xml_worker).to receive(:build).with(subject.build_path).ordered

        subject.install_components
      end

      it 'should resolve and build each component from the template type' do
        expect(CloudModel::Components::BaseComponent).to receive(:from_sym).with(:ruby).and_return(ruby_component)
        expect(CloudModel::Components::BaseComponent).to receive(:from_sym).with(:xml).and_return(xml_component)
        expect(ruby_worker).to receive(:build).with(subject.build_path)
        expect(xml_worker).to receive(:build).with(subject.build_path)

        subject.install_components
      end

      it 'should log a sub step for each component' do
        expect(subject).to receive(:comment_sub_step).with("Install Ruby")
        expect(subject).to receive(:comment_sub_step).with("Install XML")

        subject.install_components
      end

      it 'should raise if a component has no worker' do
        allow(CloudModel::Components::BaseComponent).to receive(:from_sym).with(:ruby).and_raise(NameError.new('not found'))
        allow(CloudModel).to receive(:log_exception)

        expect { subject.install_components }.to raise_error("Component :ruby has no worker")
      end
    end

    describe 'pack_template' do
      it 'should set build state to packaging and tar the template' do
        expect(template).to receive(:update_attribute).with(:build_state, :packaging)
        expect(subject).to receive(:tar_template).with(subject.build_path, template)

        subject.pack_template
      end
    end

    describe 'pack_manifest' do
      before do
        allow(subject).to receive(:mkdir_p)
        allow(subject).to receive(:render_to_remote)
        allow(host).to receive(:exec!)
      end

      it 'should render metadata.yaml' do
        expect(subject).to receive(:render_to_remote).with(
          "/cloud_model/guest_template/metadata.yaml",
          "#{subject.build_path}/metadata.yaml",
          template: template
        )
        subject.pack_manifest
      end

      it 'should render host and hostname templates' do
        %w(hosts.tpl hostname.tpl).each do |file|
          expect(subject).to receive(:render_to_remote).with(
            "/cloud_model/guest_template/#{file}",
            "#{subject.build_path}/templates/#{file}",
            template: template
          )
        end
        subject.pack_manifest
      end

      it 'should tar the metadata' do
        expect(host).to receive(:exec!).with(
          "cd #{subject.build_path} && tar czvf #{template.lxd_image_metadata_tarball} metadata.yaml templates/*",
          "Failed to write metadata"
        )
        subject.pack_manifest
      end
    end

    describe 'build_template' do
      it 'should return false if template is not pending and force is not set' do
        allow(template).to receive(:build_state).and_return(:finished)

        expect(subject.build_template(template)).to eq false
      end

      it 'should run build steps when template is pending' do
        allow(template).to receive(:build_state).and_return(:pending)
        allow(template).to receive(:update_attributes)
        allow(subject).to receive(:mkdir_p)
        allow(subject).to receive(:run_steps)

        expect(template).to receive(:update_attributes).with(build_state: :running)
        expect(subject).to receive(:run_steps).with(:build, anything, {})

        subject.build_template(template)
      end

      it 'should set build state to finished on success' do
        allow(template).to receive(:build_state).and_return(:pending)
        allow(template).to receive(:update_attributes)
        allow(subject).to receive(:mkdir_p)
        allow(subject).to receive(:run_steps)

        expect(template).to receive(:update_attributes).with(build_state: :finished, build_last_issue: "")

        subject.build_template(template)
      end

      it 'should set build state to failed on error' do
        allow(template).to receive(:build_state).and_return(:pending)
        allow(template).to receive(:update_attributes)
        allow(subject).to receive(:mkdir_p)
        allow(subject).to receive(:run_steps).and_raise(RuntimeError.new("boom"))
        allow(subject).to receive(:cleanup_chroot)
        allow(CloudModel).to receive(:log_exception)

        expect(template).to receive(:update_attributes).with(build_state: :failed, build_last_issue: "boom")
        expect { subject.build_template(template) }.to raise_error("Failed to build core image!")
      end

      it 'should run build steps with force option' do
        allow(template).to receive(:build_state).and_return(:finished)
        allow(template).to receive(:update_attributes)
        allow(subject).to receive(:mkdir_p)
        allow(subject).to receive(:run_steps)

        expect(subject).to receive(:run_steps)

        subject.build_template(template, force: true)
      end
    end
  end
end
