module CloudModel
  module Monitoring
    module Services
      class JitsiChecks < CloudModel::Monitoring::Services::BaseChecks
        def check
          do_check_for_errors_on data, {
            not_reachable:   'Jicofo reachable',
            no_jicofo_stats: 'Jicofo stats available',
            parse_result:    'Jicofo stats parsable'
          }

          # Nothing more to assert if Jicofo was unreachable/unparsable (data is
          # an error hash, so bridge counts are absent).
          return unless data.is_a?(Hash) && data['operational_bridges']

          # No usable video bridge → no conference can be hosted at all.
          do_check :jitsi_no_bridge, 'operational video bridge', {
            critical: data['operational_bridges'].to_i < 1
          }, message: "#{data['operational_bridges'].to_i} of #{data['bridge_count'].to_i} bridge(s) operational",
             value: data['operational_bridges'].to_s

          # Jicofo is up but the Videobridge's own HTTP port is dead — the JVB
          # process is likely down (Jicofo may still list a stale bridge).
          do_check :jitsi_videobridge_down, 'videobridge responding', {
            warning: data['videobridge_up'] != 1
          }, message: "Videobridge HTTP port #{@subject.videobridge_port} not responding",
             value: data['videobridge_up'] == 1 ? 'up' : 'down'
        end
      end
    end
  end
end
