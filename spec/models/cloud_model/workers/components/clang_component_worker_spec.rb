# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::ClangComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::ClangComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get clang, llvm-dev and libclang-dev' do
      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'apt-get install clang llvm-dev libclang-dev -y',
        'Failed to install LLVM/Clang'
      )

      subject.build '/tmp/build'
    end
  end
end
