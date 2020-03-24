module CloudModel
  class ServiceChecks < CloudModel::BaseChecks
    def initialize host, guest, service, options = {}
      service_check_class_name = "#{service.class.name}Checks"
      @subject = service
      
      puts "    [#{service.class.model_name.human} #{service.name}]"
      @indent = 4
      
      begin
        service_check_class = service_check_class_name.constantize
      rescue LoadError, NameError => e
        do_check :no_check, 'ServiceCheck exists', {info: true}, message: e, value: service_check_class_name
        return self
      end

      do_check :no_check, 'ServiceCheck exists', {info: false} # Resolve Issue if Check did not exist before
    
      @service_check = service_check_class.new host, guest, service, options
    end
    
    def check
      @service_check.check if @service_check
    end
  end
end