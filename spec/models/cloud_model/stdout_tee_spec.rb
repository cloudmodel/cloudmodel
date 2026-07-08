require 'spec_helper'

describe CloudModel::StdoutTee do
  it 'tees puts, print and write into the sink and restores $stdout' do
    captured = +''
    original = $stdout

    output = StringIO.new
    allow($stdout).to receive(:write) { |*args| output.write(*args) }

    described_class.capture ->(text) { captured << text } do
      puts 'hello'
      print 'a', 'b'
      $stdout.write 'c'
      $stdout << 'd'
    end

    expect($stdout).to eq original
    expect(captured).to eq "hello\nabcd"
  end

  it 'restores $stdout when the block raises' do
    original = $stdout
    sink = ->(_) {}
    expect {
      described_class.capture(sink) { raise 'boom' }
    }.to raise_error 'boom'
    expect($stdout).to eq original
  end

  it 'feeds nested captures outward even when the inner one is quiet' do
    outer = +''
    inner = +''
    allow($stdout).to receive(:write).and_return(0) # keep the real terminal quiet

    described_class.capture ->(text) { outer << text } do
      described_class.capture ->(text) { inner << text }, passthrough: false do
        $stdout.write 'nested'
      end
      $stdout.write ' outer-only'
    end

    expect(inner).to eq 'nested'
    expect(outer).to eq 'nested outer-only'
  end

  it 'never lets a failing sink break the flow' do
    sink = ->(_) { raise 'sink broken' }
    expect {
      described_class.capture(sink) { $stdout.write 'x' }
    }.not_to raise_error
  end
end
