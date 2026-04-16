module CloudModel
  module Workers
    module Components
      # Abstract base class for all component workers.
      #
      # Component workers are responsible for installing a single software
      # component (e.g. Ruby, nginx, MongoDB) into a guest template's chroot
      # environment. Subclasses implement a `build(build_path)` method that
      # runs the necessary `apt-get`, compilation, or configuration steps inside
      # the chroot.
      class BaseComponentWorker < CloudModel::Workers::BaseWorker
        # @param template [CloudModel::GuestTemplate] the template being built
        # @param host [CloudModel::Host] the host on which building runs
        # @param options [Hash] additional options (e.g. `:component` with the component instance)
        def initialize template, host, options={}
          #super host, options
          @template = template
          @host = host
          @options = options
        end
      end
    end
  end
end