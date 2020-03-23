module CloudModel
  class BaseNotifier
    def initialize options={}
      @options = options
    end
    
    def send_message subject, message
    end
  end
end