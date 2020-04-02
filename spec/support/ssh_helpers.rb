module SshHelpers
  require 'net/ssh/test'
  include Net::SSH::Test

  def story_with_new_channel
    story do |session|
      channel = session.opens_channel
      yield channel
      channel.gets_close
      channel.sends_close
    end
  end
  
  def script
    Net::SSH::Test::Extensions::IO.with_test_extension do
      yield
      expect(socket.script.events).to be_empty, "there should not be any remaining scripted events, but there are still #{socket.script.events.length} pending"
    end
  end
  
  def script_with_connection
    script do
      allow(subject).to receive(:ssh_connection).and_return connection
      yield
    end
  end
end
