STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

class String
  def to_sensor_name
    gsub(/([A-Z]+)([A-Z][a-z]\d)/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").tr(" ", "_").
    downcase
  end

  def underscore
    self.scan(/[a-z\d]+|[A-Z][a-z\d]+|[A-Z]+/).join("_").downcase
  end
end

def perfdata(data, options = {})
  prefix = options[:prefix] || ''
  
  if data
    data.map do |k,v| 
      if v.class == Array
        counter = 0
        v.map do |sv|
          counter += 1
          "#{prefix}#{k.to_s.to_sensor_name}_#{counter}=#{sv}"
        end * ', '
      elsif v.class == Hash
        perfdata v, prefix: "#{prefix}#{k.to_s.to_sensor_name}_"
      else
        "#{prefix}#{k.to_s.to_sensor_name}=#{v}"
      end
    end * ', '
  end
end