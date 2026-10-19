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

  it 'hands on valid UTF-8 only, to the sink and to the terminal' do
    captured = +''
    written = +''
    allow($stdout).to receive(:write) { |text| written << text; text.bytesize }

    described_class.capture ->(text) { captured << text } do
      $stdout.write "ok \xF0\x9F\x99\x8F broken \xF0".b
    end

    expect(captured).to eq 'ok 🙏 broken ?'
    expect(captured.encoding).to eq Encoding::UTF_8
    expect(written).to eq 'ok 🙏 broken ?'
  end

  it 'keeps the captures of parallel threads apart' do
    allow($stdout).to receive(:write).and_return(0)
    seen = { a: +'', b: +'' }
    barrier = Queue.new

    threads = %i(a b).map do |key|
      Thread.new do
        described_class.capture ->(text) { seen[key] << text }, passthrough: false do
          barrier.pop                       # both threads capture at the same time
          3.times { |i| $stdout.write "#{key}#{i} "; Thread.pass }
        end
      end
    end
    2.times { barrier.push true }
    threads.each(&:join)

    expect(seen[:a]).to eq 'a0 a1 a2 '
    expect(seen[:b]).to eq 'b0 b1 b2 '
  end

  it 'reports whether the current thread is capturing' do
    expect(described_class.capturing?).to eq false
    described_class.capture(->(_) {}, passthrough: false) do
      expect(described_class.capturing?).to eq true
      expect(Thread.new { described_class.capturing? }.value).to eq false
    end
    expect(described_class.capturing?).to eq false
  end

  it 'never lets a failing terminal break the flow' do
    allow($stdout).to receive(:write).and_raise(Encoding::UndefinedConversionError, 'terminal broken')
    captured = +''
    expect {
      described_class.capture(->(text) { captured << text }) { $stdout.write 'x' }
    }.not_to raise_error
    expect(captured).to eq 'x'
  end
end
