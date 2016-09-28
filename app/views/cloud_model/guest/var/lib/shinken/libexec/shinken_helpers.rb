STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

class String
  def to_sensor_name
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").tr(" ", "_").
    downcase
  end

  def underscore
    self.scan(/[a-z]+|[A-Z][a-z]+|[A-Z]+/).join("_").downcase
  end
end