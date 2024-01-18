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

      def check
        check_existence
      end
    end
  end
end