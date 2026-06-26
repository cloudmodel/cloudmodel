module CloudModel
  module Monitoring
    class LxdCustomVolumeChecks < CloudModel::Monitoring::BaseChecks
      def indent_size
        4
      end

      def line_prefix
        "[#{@subject.guest.host.name}] #{super}"
      end

      def acquire_data
        @subject.lxc_show
      end

      def check_existence
        do_check :existence, 'existence of volume', warning: not(@subject.volume_exists?)
      end

      # Volume fill level (%). Uses the volume's own usage_percentage, which is
      # derived from the parent guest's most recent df (the guest is checked
      # just before its volumes, so it is fresh).
      def sample_metrics
        usage = @subject.usage_percentage
        usage ? {'volume.usage' => usage} : {}
      end

      def check
        data
        check_existence
      end
    end
  end
end