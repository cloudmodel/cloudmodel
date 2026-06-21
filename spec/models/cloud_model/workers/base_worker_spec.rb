require 'spec_helper'

describe CloudModel::Workers::BaseWorker do
  let(:host) { Factory :host }
  subject { CloudModel::Workers::BaseWorker.new host }

  describe '#initialize' do
    it 'should store host' do
      expect(subject.host).to eq host
    end

    it 'should accept options' do
      worker = CloudModel::Workers::BaseWorker.new(host, skip_to: '3')
      expect(worker.host).to eq host
    end
  end

  describe '.host' do
    it 'should return the host' do
      expect(subject.host).to eq host
    end
  end

  describe '.error_log_object' do
    it 'should return the host' do
      expect(subject.error_log_object).to eq host
    end
  end

  describe 'render' do
    it 'should call render_to_string on a new instance of ActionController::Base and pass return value' do
      action_controller = double(ActionController::Base)
      allow(ActionController::Base).to receive(:new).and_return action_controller
      expect(action_controller).to receive(:render_to_string).with(template: 'my_template', locals: {a:1, b:2}, layout: false).and_return 'rendered template'
      expect(subject.render 'my_template', a: 1, b: 2).to eq 'rendered template'
    end

    it 'should translate dots to underscores' do
      action_controller = double(ActionController::Base)
      allow(ActionController::Base).to receive(:new).and_return action_controller
      expect(action_controller).to receive(:render_to_string).with(template: 'system_d/my_template_conf', locals: {a:1, b:2}, layout: false).and_return 'rendered template'
      expect(subject.render 'system.d/my_template.conf', a: 1, b: 2).to eq 'rendered template'
    end
  end

  describe '.template_exists?' do
    it 'should check view lookup context' do
      controller = double(ActionController::Base)
      lookup = double 'lookup_context'
      allow(ActionController::Base).to receive(:new).and_return(controller)
      allow(controller).to receive(:lookup_context).and_return(lookup)
      allow(lookup).to receive(:find_all).with('my_template').and_return(['found'])

      expect(subject.template_exists?('my.template')).to eq true
    end
  end

  describe '.render_to_remote' do
    it 'should render template and write via sftp' do
      allow(subject).to receive(:render).with('my.conf', {a: 1}).and_return('rendered')
      sftp = double 'sftp'
      file_handle = double 'file_handle'
      allow(host).to receive(:sftp).and_return(sftp)
      allow(sftp).to receive_message_chain(:file, :open).and_yield(file_handle)
      allow(file_handle).to receive(:puts).with('rendered')

      subject.render_to_remote('my.conf', '/etc/my.conf', {a: 1})
    end
  end

  describe '.perpare_chroot' do
    it 'should mount proc, sys, dev, dev/pts' do
      allow(host).to receive(:mounted_at?).and_return(false)
      allow(subject).to receive(:mkdir_p)
      expect(host).to receive(:exec!).exactly(4).times

      subject.prepare_chroot('/mnt/root')
    end
  end

  describe '.cleanup_chroot' do
    it 'should unmount all chroot mounts' do
      allow(host).to receive(:mounted_at?).and_return(true)
      expect(host).to receive(:exec!).exactly(4).times

      expect(subject.cleanup_chroot('/mnt/root')).to eq true
    end
  end

  describe '.chroot' do
    it 'should prepare chroot, render script, execute and cleanup' do
      allow(SecureRandom).to receive(:uuid).and_return('test-uuid')
      allow(Rails.logger).to receive(:debug)
      allow(subject).to receive(:prepare_chroot)
      allow(subject).to receive(:render_to_remote)
      allow(host).to receive(:exec).with('chroot /mnt/root /root/chroot-test-uuid.sh').and_return([true, 'output'])
      sftp = double 'sftp'
      allow(host).to receive(:sftp).and_return(sftp)
      allow(sftp).to receive(:remove!)

      expect(subject.chroot('/mnt/root', 'ls')).to eq [true, 'output']
    end
  end

  describe '.chroot!' do
    it 'should raise on failure' do
      allow(subject).to receive(:chroot).and_return([false, 'error output'])

      expect { subject.chroot!('/mnt/root', 'ls', 'Failed') }.to raise_error(RuntimeError, 'Failed: error output')
    end

    it 'should return output on success' do
      allow(subject).to receive(:chroot).and_return([true, 'output'])

      expect(subject.chroot!('/mnt/root', 'ls', 'Failed')).to eq 'output'
    end
  end

  describe '.mkdir_p' do
    it 'should exec mkdir -p on host' do
      expect(host).to receive(:exec!).with("mkdir -p /some/path", "Failed to make directory /some/path")

      subject.mkdir_p('/some/path')
    end
  end

  describe 'local_exec' do
    it 'should run command locally' do
      allow(Rails.logger).to receive(:debug)

      result = subject.local_exec('echo test')
      expect(result).to include('test')
    end
  end

  describe 'local_exec!' do
    it 'should return result on success' do
      allow(Rails.logger).to receive(:debug)

      result = subject.local_exec!('echo test', 'Failed')
      expect(result).to include('test')
    end
  end

  describe '.download_template' do
    it 'should scp template from host' do
      template = double 'template', tarball: '/inst/template.tar.bz2'
      allow(CloudModel.config).to receive(:skip_sync_images).and_return(false)
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(FileUtils).to receive(:mkdir_p)
      allow(host).to receive(:ssh_address).and_return('10.42.0.1')
      allow(subject).to receive(:local_exec!)

      subject.download_template(template)
    end

    it 'should skip if skip_sync_images is set' do
      template = double 'template'
      allow(CloudModel.config).to receive(:skip_sync_images).and_return(true)
      expect(subject).not_to receive(:local_exec!)

      subject.download_template(template)
    end
  end

  describe '.upload_template' do
    it 'should scp template to host' do
      template = double 'template', tarball: '/inst/template.tar.bz2'
      allow(CloudModel.config).to receive(:skip_sync_images).and_return(false)
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(subject).to receive(:mkdir_p)
      allow(host).to receive(:ssh_address).and_return('10.42.0.1')
      allow(subject).to receive(:local_exec!)

      subject.upload_template(template)
    end
  end

  describe 'upsync_template' do
    it 'should be defined' do
      expect(subject).to respond_to(:upsync_templates)
    end
  end

  describe '.build_tar' do
    it 'should execute tar on host' do
      expect(host).to receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2 /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar '/mnt/root', '/inst/image.tar.bz2'
    end

    it 'should parse boolean parameter' do
      expect(host).to receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2 --option /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar '/mnt/root', '/inst/image.tar.bz2', option: true
    end

    it 'should parse valued parameter' do
      expect(host).to receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2 --option test /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar '/mnt/root', '/inst/image.tar.bz2', option: 'test'
    end

    it 'should parse multiplevalued parameter' do
      expect(host).to receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2 --option test --option test2 /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar '/mnt/root', '/inst/image.tar.bz2', option: ['test', 'test2']
    end

    it 'should only put one - in front of single character options' do
      expect(host).to receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2 -j -C test /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar '/mnt/root', '/inst/image.tar.bz2', j: true, C: 'test'
    end

    it 'should escape values' do
      expect(host).to receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2\\;\\ mkfs.ext2\\ /dev/sda --option\\;\\ echo\\ /dev/random\\ /etc/passwd\\; test\\;\\ rsync\\ /\\ bad_host:/pirate\\; /mnt/root\\;\\ rm\\ -rf\\ /\\;", "Failed to build tar /inst/image.tar.bz2; mkfs.ext2 /dev/sda").and_return 'ok'
      subject.build_tar '/mnt/root; rm -rf /;', '/inst/image.tar.bz2; mkfs.ext2 /dev/sda', 'option; echo /dev/random /etc/passwd;' => 'test; rsync / bad_host:/pirate;'
    end
  end

  describe '.run_step_command' do
    it 'should execute command on host' do
      allow(subject).to receive(:error_log_object).and_return(host)
      allow(subject).to receive(:ls)
      allow(Rails.logger).to receive(:debug)

      expect { subject.run_step_command(:deploy, 'ls', ['List files', :ls], {}) }.to output.to_stdout
    end
  end

  describe '.parse_step_skip_to' do
    it 'should parse step number and remainder' do
      expect(subject.parse_step_skip_to('3.2.1')).to eq ['2.1', 3]
    end

    it 'should return zero for empty string' do
      expect(subject.parse_step_skip_to('')).to eq ['', 0]
    end
  end

  describe '.current_indent' do
    it 'should default to 2' do
      expect(subject.current_indent).to eq 2
    end
  end

  describe '.increase_indent' do
    it 'should increase indent by 2' do
      subject.increase_indent
      expect(subject.current_indent).to eq 4
    end
  end

  describe '.decrease_indent' do
    it 'should decrease indent by 2' do
      subject.increase_indent
      subject.decrease_indent
      expect(subject.current_indent).to eq 2
    end
  end

  describe '.debug' do
    it 'should print debug message' do
      expect { subject.debug('test') }.to output(/test/).to_stdout
    end
  end

  describe '.comment_sub_step' do
    it 'should print sub step comment' do
      expect { subject.comment_sub_step('doing something') }.to output(/doing something/).to_stdout
    end
  end

  describe '.run_steps' do
    it 'should execute steps sequentially' do
      allow(Rails.logger).to receive(:debug)
      allow(subject).to receive(:run_step_command)

      expect { subject.run_steps(:deploy, [['Step 1', :step1]], {}) }.to output(/Step 1/).to_stdout
    end
  end
end