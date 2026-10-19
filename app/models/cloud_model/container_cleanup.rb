module CloudModel
  # Removes the stopped containers a guest accumulates: every redeploy builds
  # a new one and leaves the previous one behind as the rollback, and nothing
  # ever pruned them — a dozen full rootfs clones per guest after a few
  # years, tens of GB each on image-based hosts.
  #
  # Kept are, per guest, the newest `keep` containers (the running one among
  # them — it is never touched, whatever its position — plus the rollback
  # headroom). Everything older that is not running goes: the LXD container,
  # its dataset (lxc delete) and the document.
  #
  # Driven by `rake cloudmodel:cleanup:containers` (dry run unless CONFIRM=1).
  class ContainerCleanup
    attr_reader :keep

    def initialize keep: 3
      @keep = [keep.to_i, 1].max
    end

    # Containers that would go, per guest: `[guest, [containers]]`.
    # @param guests [Enumerable<Guest>]
    def removable guests
      guests.map do |guest|
        containers = guest.lxd_containers.to_a.sort_by { |c| c.created_at || Time.at(0) }.reverse
        current = guest.current_lxd_container
        stale = containers.drop(keep).reject { |c| c == current }
        [guest, stale]
      end.reject { |_guest, stale| stale.empty? }
    end

    # @param dry_run [Boolean] report only
    # @param output [IO]
    # @return [Hash] `{ removed: Integer, failed: Integer, bytes: Integer }` (bytes: `zfs used` of what was/would be removed, where known)
    def cleanup! guests, dry_run: true, output: $stdout
      result = { removed: 0, failed: 0, bytes: 0 }

      removable(guests).each do |guest, stale|
        output.puts "#{guest.name} (#{guest.host.name}): #{stale.size} of #{guest.lxd_containers.count} container(s) to remove"
        stale.each do |container|
          used = dataset_used container
          result[:bytes] += used.to_i
          if container.running?
            output.puts "  keep    #{container.name} — running"
            next
          end
          if dry_run
            output.puts "  would remove #{container.name} (#{human used})"
            next
          end
          begin
            unless container.destroy
              raise "destroy refused"
            end
            output.puts "  removed #{container.name} (#{human used})"
            result[:removed] += 1
          rescue Exception => e
            CloudModel.log_exception e
            output.puts "  FAILED  #{container.name}: #{e.message.lines.first.to_s.strip}"
            result[:failed] += 1
          end
        end
      end

      verb = dry_run ? 'would free' : 'freed'
      output.puts "\n#{dry_run ? 'Dry run — nothing removed' : "Removed #{result[:removed]} container(s), #{result[:failed]} failed"}; #{verb} about #{human result[:bytes]}."
      result
    end

    private

    def dataset_used container
      ok, out = container.host.exec "zfs list -H -p -o used #{container.root_dataset.shellescape}"
      ok ? out.to_s.strip.to_i : nil
    end

    def human bytes
      return '?' if bytes.nil?
      units = %w(B K M G T)
      value = bytes.to_f
      unit = 0
      while value >= 1024 && unit < units.size - 1
        value /= 1024
        unit += 1
      end
      "#{value.round(unit == 0 ? 0 : 1)}#{units[unit]}"
    end
  end
end
