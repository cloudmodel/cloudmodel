module CloudModel
  module Livestatus
    
    STATES = {
      -1 => :undefined,
      0 => :running,
      1 => :warning,
      2 => :critical,
      3 => :unknown,
      4 => :dependent
    }
  end
end