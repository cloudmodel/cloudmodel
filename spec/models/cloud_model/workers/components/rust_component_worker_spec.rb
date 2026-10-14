# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::RustComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  let(:component) {double CloudModel::Components::RustComponent, version: nil}
  subject {CloudModel::Workers::Components::RustComponentWorker.new template, host, component: component}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'rustversion' do
    it 'should default to "stable" when no version is set' do
      expect(subject.rustversion).to eq 'stable'
    end

    it 'should return the component version when set' do
      allow(component).to receive(:version).and_return('1.95')
      expect(subject.rustversion).to eq '1.95'
    end
  end

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
      allow(subject).to receive :mkdir_p
      allow(host).to receive :exec
      allow(host).to receive :exec!
    end

    it 'should export the toolchain homes for every shell in the build root' do
      expect(host).to receive(:exec!).with(
        "printf '%s\\n' 'export CARGO_HOME=/usr/local/cargo' 'export RUSTUP_HOME=/usr/local/rustup' 'export PATH=/usr/local/cargo/bin:$PATH' > /tmp/build/etc/profile.d/rust.sh && chmod 644 /tmp/build/etc/profile.d/rust.sh",
        'Failed to write the Rust environment'
      )
      subject.build '/tmp/build'
    end

    it 'should link the proxies and homes inside the build root, not on the host' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'ln -sf /usr/local/cargo/bin/cargo /usr/local/bin/cargo && ln -sf /usr/local/cargo/bin/rustc /usr/local/bin/rustc && ln -sfn /usr/local/rustup /root/.rustup && ln -sfn /usr/local/cargo /root/.cargo',
        'Failed to link the Rust toolchain'
      )
      expect(host).not_to receive(:exec).with(/ln -sf/)
      subject.build '/tmp/build'
    end

    it 'should install the rust toolchain via rustup with the default toolchain' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        "CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup sh -s -- -y --default-toolchain stable --no-modify-path",
        'Failed to install Rust toolchain'
      )

      subject.build '/tmp/build'
    end

    it 'should install the rust toolchain with the given version' do
      allow(component).to receive(:version).and_return('1.95')
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        "CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup sh -s -- -y --default-toolchain 1.95 --no-modify-path",
        'Failed to install Rust toolchain'
      )

      subject.build '/tmp/build'
    end

    it 'should make the profile.d directory' do
      expect(subject).to receive(:mkdir_p).with('/tmp/build/etc/profile.d')

      subject.build '/tmp/build'
    end




  end
end
