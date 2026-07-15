# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::GuestTemplateWorker do
  let(:host) { double CloudModel::Host, arch: 'amd64', ssh_address: '10.0.0.1', sftp: double('sftp') }
  subject { CloudModel::Workers::GuestTemplateWorker.new host }

  describe 'build_path' do
    it 'should return the rootfs inside the core template build volume for GuestCoreTemplate' do
      template = double CloudModel::GuestCoreTemplate,
        build_volume: CloudModel::BuildZfsVolume.new(host, 'guests/build/core/core123', mountpoint: '/cloud/build/core/core123')
      subject.instance_variable_set :@template, template

      expect(subject.build_path).to eq '/cloud/build/core/core123/rootfs'
    end

    it 'should return the rootfs inside the template build volume for GuestTemplate' do
      template = double CloudModel::GuestTemplate,
        build_volume: CloudModel::BuildZfsVolume.new(host, 'guests/build/type456/tmpl789', mountpoint: '/cloud/build/type456/tmpl789')
      subject.instance_variable_set :@template, template

      expect(subject.build_path).to eq '/cloud/build/type456/tmpl789/rootfs'
    end
  end

  describe 'zfs_volume' do
    it 'should get the BuildZfsVolume from the template' do
      template = double CloudModel::GuestCoreTemplate
      volume = double CloudModel::BuildZfsVolume
      allow(template).to receive(:build_volume).with(host).and_return(volume)
      subject.instance_variable_set :@template, template

      expect(subject.zfs_volume).to eq volume
    end

    it 'should memoize the volume' do
      template = double CloudModel::GuestCoreTemplate
      volume = double CloudModel::BuildZfsVolume
      expect(template).to receive(:build_volume).once.and_return(volume)
      subject.instance_variable_set :@template, template

      expect(subject.zfs_volume).to eq subject.zfs_volume
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
    let(:core_template) do
      double CloudModel::GuestCoreTemplate,
        id: 'core1',
        build_dataset: 'guests/build/core/core1',
        build_mountpoint: '/cloud/build/core/core1'
    end
    let(:template) do
      double CloudModel::GuestTemplate,
        id: 'tmpl1',
        template_type: template_type,
        core_template: core_template,
        os_version: 'ubuntu-22.04',
        created_at: Time.now,
        build_dataset: 'guests/build/type1/tmpl1',
        build_mountpoint: '/cloud/build/type1/tmpl1',
        build_volume: CloudModel::BuildZfsVolume.new(host, 'guests/build/type1/tmpl1', mountpoint: '/cloud/build/type1/tmpl1')
    end
    let(:zfs_volume) { double CloudModel::BuildZfsVolume, rootfs_path: '/cloud/build/type1/tmpl1/rootfs' }

    before do
      subject.instance_variable_set :@template, template
    end

    describe 'prepare_build_volume' do
      before do
        allow(subject).to receive(:zfs_volume).and_return(zfs_volume)
        allow(subject).to receive(:mkdir_p)
      end

      it 'should prepare a fresh volume' do
        expect(zfs_volume).to receive(:prepare!)
        expect(subject).to receive(:mkdir_p).with(subject.build_path)

        subject.prepare_build_volume
      end

      it 'should prepare a fresh volume even over the leftover of a failed build' do
        allow(zfs_volume).to receive(:dataset_exists?).and_return(true)
        allow(zfs_volume).to receive(:ready?).and_return(false)
        expect(zfs_volume).to receive(:prepare!)

        subject.prepare_build_volume
      end

      context 'when resuming with skip_to' do
        before do
          subject.instance_variable_set :@build_options, {skip_to: '3'}
        end

        it 'should reuse an uncommitted volume' do
          allow(zfs_volume).to receive(:dataset_exists?).and_return(true)
          allow(zfs_volume).to receive(:ready?).and_return(false)
          expect(zfs_volume).not_to receive(:prepare!)
          expect(zfs_volume).to receive(:mount!)

          subject.prepare_build_volume
        end

        it 'should prepare a fresh volume over a committed one' do
          allow(zfs_volume).to receive(:dataset_exists?).and_return(true)
          allow(zfs_volume).to receive(:ready?).and_return(true)
          expect(zfs_volume).to receive(:prepare!)

          subject.prepare_build_volume
        end
      end
    end

    describe 'commit_build_volume' do
      it 'should cleanup the chroot, commit the snapshot and unmount' do
        allow(subject).to receive(:zfs_volume).and_return(zfs_volume)
        expect(subject).to receive(:cleanup_chroot).with(subject.build_path).ordered
        expect(zfs_volume).to receive(:commit!).ordered
        expect(zfs_volume).to receive(:unmount!).ordered

        subject.commit_build_volume
      end
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
        expect(subject).to receive(:chroot!).with(subject.build_path, "apt-get install sudo rsync wget curl unzip -y", "Failed to install rsync, wget, curl, and unzip")
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

    describe 'write_lxd_metadata' do
      before do
        allow(subject).to receive(:mkdir_p)
        allow(subject).to receive(:render_to_remote)
      end

      it 'should render metadata.yaml at the build volume root' do
        expect(subject).to receive(:render_to_remote).with(
          "/cloud_model/guest_template/metadata.yaml",
          "/cloud/build/type1/tmpl1/metadata.yaml",
          template: template
        )
        subject.write_lxd_metadata
      end

      it 'should render host and hostname templates' do
        expect(subject).to receive(:mkdir_p).with("/cloud/build/type1/tmpl1/templates")
        %w(hosts.tpl hostname.tpl).each do |file|
          expect(subject).to receive(:render_to_remote).with(
            "/cloud_model/guest_template/#{file}",
            "/cloud/build/type1/tmpl1/templates/#{file}",
            template: template
          )
        end
        subject.write_lxd_metadata
      end
    end

    describe 'ensure_core_template' do
      let(:core_volume) { double CloudModel::BuildZfsVolume }

      before do
        allow(core_template).to receive(:build_volume).with(host).and_return(core_volume)
        allow(subject).to receive(:comment_sub_step)
      end

      it 'should return the core template if its volume is ready on the host' do
        allow(core_volume).to receive(:ready?).and_return(true)
        expect(core_template).not_to receive(:ensure_build_volume!)

        expect(subject.ensure_core_template).to eq core_template
      end

      it 'should sync or build the core template volume if missing on the host' do
        allow(core_volume).to receive(:ready?).and_return(false)
        expect(core_template).to receive(:ensure_build_volume!).with(host)

        expect(subject.ensure_core_template).to eq core_template
      end

      it 'should create a core template if the template has none' do
        allow(template).to receive(:core_template).and_return(nil, core_template)
        expect(template).to receive(:update_attributes) do |attrs|
          expect(attrs[:core_template]).to eq core_template
        end
        allow(CloudModel::GuestCoreTemplate).to receive(:create!).with(arch: 'amd64', os_version: 'ubuntu-22.04').and_return(core_template)
        allow(core_volume).to receive(:ready?).and_return(true)

        expect(subject.ensure_core_template).to eq core_template
      end
    end

    describe 'cleanup_template' do
      before do
        allow(subject).to receive(:zfs_volume).and_return(zfs_volume)
        allow(zfs_volume).to receive(:scrub_identity!)
        allow(subject).to receive(:comment_sub_step)
        allow(subject).to receive(:chroot!)
        allow(subject).to receive(:render_to_remote)
        allow(host).to receive(:exec!)
      end

      it 'should clean apt caches' do
        expect(subject).to receive(:chroot!).with(subject.build_path, "apt-get clean", "Failed to clean apt caches")
        subject.cleanup_template
      end

      it 'should scrub identity data and enable ssh host key regeneration on first boot' do
        expect(zfs_volume).to receive(:scrub_identity!)
        expect(subject).to receive(:render_to_remote).with(
          "/cloud_model/guest/etc/systemd/system/regenerate_ssh_host_keys.service",
          "#{subject.build_path}/etc/systemd/system/regenerate_ssh_host_keys.service"
        )
        expect(subject).to receive(:chroot!).with(
          subject.build_path,
          "ln -sf /etc/systemd/system/regenerate_ssh_host_keys.service /etc/systemd/system/multi-user.target.wants/regenerate_ssh_host_keys.service",
          "Failed to enable ssh host key regeneration"
        )
        subject.cleanup_template
      end

      it 'should clear temporary files and docs' do
        expect(host).to receive(:exec!).with(
          "rm -rf #{subject.build_path}/tmp/* #{subject.build_path}/var/tmp/* #{subject.build_path}/run/* #{subject.build_path}/var/cache/* #{subject.build_path}/usr/share/man/* #{subject.build_path}/usr/share/doc/*",
          "Failed to clear temporary files"
        )
        subject.cleanup_template
      end
    end

    describe 'clone_core_template' do
      it 'should clone the core template volume and refresh resolv.conf' do
        allow(subject).to receive(:ensure_core_template).and_return(core_template)
        allow(subject).to receive(:zfs_volume).and_return(zfs_volume)
        expect(zfs_volume).to receive(:prepare_from!).with('guests/build/core/core1')
        expect(host).to receive(:exec!).with("cp /etc/resolv.conf #{subject.build_path}/etc", "Failed to copy resolve conf")

        subject.clone_core_template
      end
    end

    describe 'build_template' do
      before do
        allow(subject).to receive(:zfs_volume).and_return(zfs_volume)
        allow(template).to receive(:update_attributes)
        allow(subject).to receive(:run_steps)
      end

      it 'should return false if template is not pending and force is not set' do
        allow(template).to receive(:build_state).and_return(:finished)

        expect(subject.build_template(template)).to eq false
      end

      it 'should run build steps when template is pending' do
        allow(template).to receive(:build_state).and_return(:pending)

        expect(template).to receive(:update_attributes).with(build_state: :running)
        expect(subject).to receive(:run_steps).with(:build, anything, {})

        subject.build_template(template)
      end

      it 'should set build state to finished on success' do
        allow(template).to receive(:build_state).and_return(:pending)

        expect(template).to receive(:update_attributes).with(build_state: :finished, build_last_issue: "", build_host: host)

        subject.build_template(template)
      end

      it 'should set build state to failed and mark the volume on error' do
        allow(template).to receive(:build_state).and_return(:pending)
        allow(subject).to receive(:run_steps).and_raise(RuntimeError.new("boom"))
        allow(subject).to receive(:cleanup_chroot)
        allow(CloudModel).to receive(:log_exception)

        expect(template).to receive(:update_attributes).with(build_state: :failed, build_last_issue: "boom")
        expect(subject).to receive(:cleanup_chroot).with(subject.build_path)
        expect(zfs_volume).to receive(:fail!)
        expect { subject.build_template(template) }.to raise_error("Failed to build guest template!")
      end

      it 'should run build steps with force option' do
        allow(template).to receive(:build_state).and_return(:finished)

        expect(subject).to receive(:run_steps)

        subject.build_template(template, force: true)
      end

      it 'should print prepend_output when given' do
        allow(template).to receive(:build_state).and_return(:pending)

        expect(subject).to receive(:puts).with('hello')

        subject.build_template(template, prepend_output: 'hello')
      end
    end
  end

  context 'with a core template' do
    let(:core_template) do
      double CloudModel::GuestCoreTemplate,
        id: 'core1',
        os_version: 'ubuntu-22.04',
        build_dataset: 'guests/build/core/core1',
        build_mountpoint: '/cloud/build/core/core1',
        build_volume: CloudModel::BuildZfsVolume.new(host, 'guests/build/core/core1', mountpoint: '/cloud/build/core/core1')
    end
    let(:zfs_volume) { double CloudModel::BuildZfsVolume, rootfs_path: '/cloud/build/core/core1/rootfs' }

    before do
      subject.instance_variable_set :@template, core_template
    end

    describe 'build_path' do
      it 'should return the rootfs inside the core build volume' do
        expect(subject.build_path).to eq '/cloud/build/core/core1/rootfs'
      end
    end

    describe 'build_core_template' do
      before do
        allow(subject).to receive(:os_version).and_return('ubuntu-22.04')
        allow(subject).to receive(:zfs_volume).and_return(zfs_volume)
        allow(subject).to receive(:run_steps)
        allow(subject).to receive(:cleanup_chroot)
        allow(core_template).to receive(:update_attributes)
      end

      it 'should return false if not pending and force not set' do
        allow(core_template).to receive(:build_state).and_return(:finished)
        expect(subject.build_core_template(core_template)).to eq false
      end

      it 'should run build steps when pending' do
        allow(core_template).to receive(:build_state).and_return(:pending)

        expect(core_template).to receive(:update_attributes).with(build_state: :running, os_version: 'ubuntu-22.04')
        expect(subject).to receive(:run_steps).with(:build, anything, {})
        expect(core_template).to receive(:update_attributes).with(build_state: :finished, build_last_issue: "", build_host: host)

        expect(subject.build_core_template(core_template)).to eq core_template
      end

      it 'should build when forced even if not pending' do
        allow(core_template).to receive(:build_state).and_return(:finished)

        expect(subject).to receive(:run_steps)
        subject.build_core_template(core_template, force: true)
      end

      it 'should set build state to failed, clean up and mark the volume on error' do
        allow(core_template).to receive(:build_state).and_return(:pending)
        allow(subject).to receive(:run_steps).and_raise(RuntimeError.new("kaboom"))
        allow(CloudModel).to receive(:log_exception)

        expect(core_template).to receive(:update_attributes).with(build_state: :failed, build_last_issue: "kaboom")
        expect(subject).to receive(:cleanup_chroot).with(subject.build_path)
        expect(zfs_volume).to receive(:fail!)
        expect { subject.build_core_template(core_template) }.to raise_error("Failed to build core image!")
      end

      it 'should print prepend_output when given' do
        allow(core_template).to receive(:build_state).and_return(:pending)
        expect(subject).to receive(:puts).with('starting')
        subject.build_core_template(core_template, prepend_output: 'starting')
      end
    end
  end
end
