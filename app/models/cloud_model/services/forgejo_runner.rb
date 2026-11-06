require "tmpdir"
module CloudModel
  module Services
    # Forgejo Actions runner embedded in a {Guest}.
    #
    # Runs the `forgejo-runner` daemon that fetches workflow jobs from a
    # Forgejo instance and executes them directly in this guest (`host`
    # labels): the guest *is* the job environment. Its template is built like
    # any other from components, so the tool chain the workflows need (ruby,
    # nodejs, rust, mongodb, …) is simply added as {Base#additional_components}
    # and databases the test suites expect run as ordinary services in the
    # same guest. No container engine, no LXD nesting.
    #
    # The runner therefore belongs into a guest of its own: a job (or anyone
    # who may push a workflow) can do anything the `forgejo-runner` user can,
    # and the guest is disposable — a redeploy restores it from the template,
    # the only state is the registration secret kept on this service.
    #
    # Registration is offline: the shared 40-hex secret is generated here,
    # rendered into the runner config and handed to the {Forgejo} service,
    # which registers the runner with `forgejo-cli actions register` on every
    # deploy (and live, right after this runner was deployed).
    class ForgejoRunner < Base
      LOG_LEVELS = %w[trace debug info warn error fatal].freeze
      DEFAULT_LABELS = ["ubuntu-latest:host", "self-hosted:host"].freeze
      HOME = "/var/lib/forgejo-runner".freeze

      # @!attribute [rw] forgejo_service_id
      #   @return [String, nil] id of the {Forgejo} service this runner registers with
      field :forgejo_service_id, type: String, default: nil

      # @!attribute [rw] instance_url
      #   @return [String, nil] Forgejo base URL; blank derives it from the
      #     linked service's guest (`https://<external hostname>/`)
      field :instance_url, type: String, default: nil

      # @!attribute [rw] runner_name
      #   @return [String, nil] name shown in Forgejo's runner list; blank uses the guest name
      field :runner_name, type: String, default: nil

      # @!attribute [rw] registration_secret
      #   @return [String, nil] 40 hex chars shared with Forgejo; generated at first deploy
      field :registration_secret, type: String, default: nil

      # @!attribute [rw] ssh_private_key
      #   @return [String, nil] ed25519 private key of the runner user, generated
      #     at the first deploy; jobs clone git-source gems over SSH with it
      field :ssh_private_key, type: String, default: nil

      # @!attribute [rw] ssh_public_key
      #   @return [String, nil] public part, to be registered on a read-only
      #     account of the instance (shown in the admin UI)
      field :ssh_public_key, type: String, default: nil

      # @!attribute [rw] labels
      #   @return [Array<String>] runner labels (`<name>:host`); jobs pick the
      #     runner through `runs-on`. Blank uses {DEFAULT_LABELS}.
      field :labels, type: Array, default: []

      # @!attribute [rw] capacity
      #   @return [Integer] jobs executed concurrently (they share the guest)
      field :capacity, type: Integer, default: 1

      # @!attribute [rw] scope
      #   @return [String, nil] `{owner}[/{repo}]` the runner serves; blank = whole instance
      field :scope, type: String, default: nil

      # @!attribute [rw] log_level
      #   @return [String] runner log level
      field :log_level, type: String, default: "info"

      # @!attribute [rw] runner_version
      #   @return [String, nil] forgejo-runner release; blank uses the component worker default
      field :runner_version, type: String, default: nil

      validates :registration_secret, format: { with: /\A\h{40}\z/ }, allow_blank: true
      validates :capacity, numericality: { greater_than: 0 }
      validates :log_level, inclusion: { in: LOG_LEVELS }
      validate :labels_must_be_well_formed
      validate :instance_must_be_known

      def kind
        :forgejo_runner
      end

      def components_needed
        ([:"forgejo_runner@#{effective_runner_version}"] + super).uniq
      end

      # The daemon only opens outbound connections (plus a cache server on a
      # random local port), nothing to reserve on the guest.
      def used_ports
        []
      end

      # @return [String] the forgejo-runner release this service runs on
      def effective_runner_version
        runner_version.presence || CloudModel::Workers::Components::ForgejoRunnerComponentWorker::FORGEJO_RUNNER_VERSION
      end

      # @return [CloudModel::Services::Forgejo, nil] the linked Forgejo service
      def forgejo_service
        return nil if forgejo_service_id.blank?

        owner = CloudModel::Guest.where("services._id" => BSON::ObjectId.from_string(forgejo_service_id)).first
        service = owner && owner.services.where(_id: forgejo_service_id).first
        service.is_a?(CloudModel::Services::Forgejo) ? service : nil
      rescue BSON::Error::InvalidObjectId
        nil
      end

      # @return [String, nil] URL the runner connects to
      def effective_instance_url
        return instance_url if instance_url.present?

        forgejo_service&.root_url
      end

      # Host name of the instance, for the runner user's SSH config.
      # @return [String, nil]
      def instance_host
        URI.parse(effective_instance_url.to_s).host rescue nil
      end

      # Generates the runner user's ed25519 key pair (once).
      # @return [Boolean] whether a key was generated
      def ensure_ssh_key!
        return false if ssh_private_key.present?

        Dir.mktmpdir do |dir|
          file = File.join(dir, 'id_ed25519')
          system('ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', "#{effective_runner_name} (forgejo-runner)", '-f', file) or raise "ssh-keygen failed"
          self.ssh_private_key = File.read(file)
          self.ssh_public_key = File.read("#{file}.pub").strip
        end
        save
        true
      end

      # @return [String] name registered with Forgejo
      def effective_runner_name
        runner_name.presence || guest.name
      end

      # @return [Array<String>] labels in effect
      def effective_labels
        labels.presence || DEFAULT_LABELS
      end

      # @return [Array<String>] the label names (`ubuntu-latest` of `ubuntu-latest:host`)
      def label_names
        effective_labels.map { |l| l.to_s.split(':', 2).first }
      end

      # Labels as one editable line (`ubuntu-latest:host, self-hosted:host`).
      # @return [String]
      def labels_list
        labels.join(', ')
      end

      # @param value [String] comma or whitespace separated labels
      def labels_list=(value)
        self.labels = value.to_s.split(/[\s,]+/).reject(&:blank?)
      end

      # @return [Boolean] whether the template carries an RVM ruby (`ruby@<version>` component)
      def ruby?
        additional_components.map(&:to_s).any? { |c| c.split('@', 2).first == 'ruby' }
      end

      # @return [Boolean] whether the template carries a Rust tool chain
      def rust?
        additional_components.map(&:to_s).any? { |c| c.split('@', 2).first == 'rust' }
      end

      # Environment every job step runs with: the tool chains the components
      # put into the template, reachable without a login shell. RVM only
      # wires itself into profile.d, so its default-ruby wrappers go first
      # on the PATH; bundler installs into a directory the runner user owns
      # (the RVM gem dir is root's). rustup likewise.
      #
      # @return [Hash{String => String}]
      def job_environment
        path = []
        env = {}

        if ruby?
          path << "/usr/local/rvm/wrappers/default"
          env['BUNDLE_PATH'] = "#{HOME}/gems"
        end

        if rust?
          path << "/usr/local/cargo/bin"
          env['CARGO_HOME'] = "#{HOME}/.cargo"
          env['RUSTUP_HOME'] = "/usr/local/rustup"
        end

        env['PATH'] = (path + %w[/usr/local/bin /usr/bin /bin]).join(':')
        env['HOME'] = HOME
        env
      end

      # The runner's id on the Forgejo side. Forgejo derives it from the first
      # 16 characters of the shared secret (their bytes in hex, UUID-grouped),
      # so both sides agree without talking to each other.
      #
      # @return [String, nil]
      def runner_uuid
        return nil if registration_secret.blank?

        hex = registration_secret[0, 16].unpack1('H*')
        [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join('-')
      end

      # @return [Hash] `{state: 'active'}` or an error hash for the monitoring
      def service_status
        success, output = guest.exec "systemctl is-active forgejo_runner"
        state = output.to_s.strip

        if success && state == 'active'
          {state: state}
        else
          {key: :inactive, error: "forgejo_runner is #{state.presence || 'unknown'}", severity: :critical}
        end
      rescue Exception => e
        {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
      end

      private

      def labels_must_be_well_formed
        labels.each do |label|
          errors.add :labels, :invalid unless label.to_s =~ /\A[A-Za-z0-9][A-Za-z0-9_.\-]*:host\z/
        end
      end

      def instance_must_be_known
        errors.add :forgejo_service_id, :blank if forgejo_service_id.blank? && instance_url.blank?
      end
    end
  end
end
