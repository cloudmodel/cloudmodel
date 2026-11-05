# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::ReleaseSignature do
  let(:worker) { double 'worker' }
  let(:fingerprint) { 'EB114F5E6C0DC2BCDD183550A4B61A2DC5923710' }

  it 'should import the key by fingerprint, verify the detached signature against it and stop the gpg daemons' do
    expect(worker).to receive(:chroot!).with('/tmp/build', "curl -fsSL https://keys.openpgp.org/vks/v1/by-fingerprint/#{fingerprint} | gpg --batch --no-tty --import", "Failed to import release key #{fingerprint} for forgejo 15.0.11").ordered
    expect(worker).to receive(:chroot!).with('/tmp/build', %r{gpg --batch --no-tty --status-fd 1 --verify /tmp/forgejo\.asc /tmp/forgejo \| grep -qE .*VALIDSIG.*#{fingerprint}}, "Release signature of forgejo 15.0.11 does not verify against #{fingerprint}").ordered
    expect(worker).to receive(:chroot).with('/tmp/build', 'gpgconf --kill all').ordered

    described_class.verify! worker, '/tmp/build', fingerprint, '/tmp/forgejo', 'forgejo 15.0.11'
  end
end
