module CloudModel
  module Workers
    # Worker that builds and redeploys a {CloudModel::WebImage} Rails application.
    #
    # Build pipeline (per arch, native on the arch's build host):
    #   1. git clone/pull LOCALLY on the admin machine (keeps the github deploy
    #      credentials where they already are) → source tree.
    #   2. clone the shared build-env {GuestTemplate}'s `@ready` snapshot (see
    #      {WebImage#build_env_template} — ruby+rust+node toolchain, no nginx)
    #      into a throwaway build-system dataset.
    #   3. create the app ZFS volume mounted at the build system's
    #      `/var/www/rails`, rsync the source into `current/`.
    #   4. inside a chroot into the build system: `bundle install`, `yarn
    #      install`, `assets:precompile` — native extensions link against the
    #      exact libraries the guest runs.
    #   5. commit the app volume as an `@ready` snapshot; destroy the build
    #      system. Deploy `zfs clone`s the snapshot into the guest.
    #
    # The build console streams over the existing `web_images` ActionCable
    # change-stream: worker stdout is teed into {WebImage#append_to_build_log},
    # whose DB writes poke the live-status socket (no polling).
    #
    # Redeploy triggers a rolling redeploy on each nginx service that references
    # this web image.
    class WebImageWorker < BaseWorker
      # GIT_SSH_COMMAND pointing at the injected deploy key — forces bundler's
      # git clones to use it regardless of the chroot's HOME/.ssh resolution.
      GIT_SSH_COMMAND = "GIT_SSH_COMMAND='ssh -i /root/.ssh/id_git -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'"

      # Bundler settings, passed via ENV (not `bundle config set --local`, which
      # refuses to overwrite values the app ships in .bundle/config). BUNDLE_PATH
      # must be set for EVERY bundler invocation — bundle install AND the later
      # `bundle exec rake assets:precompile` — or the latter looks for the gems
      # (incl. git-source ones) in the default system path and fails.
      BUNDLE_ENV = "BUNDLE_DEPLOYMENT=true BUNDLE_PATH=./bundle BUNDLE_WITHOUT='development:test' BUNDLE_JOBS=1"

      # Rails app root inside the build-system chroot. Just a staging mount for
      # the app volume — the committed artifact's dataset root IS the Rails
      # root, so deploy mounts it straight at releases/<id> (Capistrano-style,
      # `current` symlinks to it).
      CHROOT_APP_ROOT = '/webimage'

      # Excluded when transferring the git checkout to the build host: VCS/dev
      # cruft, plus artifacts rebuilt inside the chroot (bundle/, node_modules/,
      # compiled assets). node_modules and bundle are DELIBERATELY rebuilt there
      # (native, correct arch) and kept in the final artifact.
      APP_TRANSFER_EXCLUDES = %w(
        .git .gitignore .rspec tmp log spec test features doc
        .playwright-mcp vendor/cache node_modules bundle .cache
        public/assets public/vite
      ).freeze

      def initialize(host, web_image)
        @host = host
        @web_image = web_image
      end

      def error_log_object
        @web_image
      end

      # Builds the app artifact for one arch on this build host.
      def build_app_volume(arch, options = {})
        @arch = arch
        @web_image.update_attributes build_state: :running, build_last_issue: nil, build_log: ''

        with_build_log do
          begin
            @web_image.update_attribute :build_state, :checking_out
            checkout_git

            @web_image.update_attribute :build_state, :bundling
            prepare_build_env
            install_build_prerequisites
            configure_git_credentials
            bundle_image
            pin_ruby_version
            write_bundle_config
            yarn_install

            if @web_image.has_assets
              @web_image.update_attribute :build_state, :building_assets
              build_assets
            end

            @web_image.update_attribute :build_state, :storing
            finalize_app_volume

            @web_image.update_attribute :build_state, :finished
            true
          rescue Exception => e
            CloudModel.log_exception e
            @web_image.update_attributes build_state: :failed, build_last_issue: "#{e}"
            cleanup_build_env
            false
          end
        end
      end

      # ---- build steps ----

      # Clone/refresh the repository on the admin machine (where the github
      # deploy key lives). Raises on failure (caught by build_app_volume).
      def checkout_git
        FileUtils.mkdir_p @web_image.build_path
        path = @web_image.build_path.shellescape

        unless File.directory? "#{@web_image.build_path}/.git"
          run_with_clean_env "Cloning", "git clone #{@web_image.git_server.shellescape}:#{@web_image.git_repo.shellescape} #{path}"
        end

        # The build dir is a disposable workspace: earlier builds may have
        # rewritten tracked files. Discard local changes and hard-reset to the
        # remote branch head.
        run_with_clean_env "Pulling",
          "cd #{path} && git fetch && git checkout -f #{@web_image.git_branch.shellescape} && git reset --hard origin/#{@web_image.git_branch.shellescape}"

        commit = run_with_clean_env("Get Version", "cd #{path} && git log -1 --format=%H").to_s.strip
        @web_image.update_attribute :git_commit, commit
      end

      def prepare_build_env
        build_env = @web_image.build_env_template(@host)
        comment_sub_step "Ensure build environment #{build_env.id} on #{@host.name}"
        build_env.ensure_build_volume! @host

        comment_sub_step "Clone build system from build environment #{build_env.id}"
        buildsys_volume.prepare_from! build_env.build_dataset
        @host.exec! "cp /etc/resolv.conf #{buildsys_volume.rootfs_path.shellescape}/etc/resolv.conf", "Failed to copy resolv.conf into build system"

        comment_sub_step "Prepare workspace"
        if app_volume.dataset_exists?
          # Persistent workspace across builds — bundle/, node_modules/, the
          # git-gem caches and puppeteer's Chromium survive, so rebuilds are
          # incremental. Just remount it into this build's fresh build system.
          @host.exec! "zfs set mountpoint=#{app_volume.mountpoint.shellescape} #{app_volume.dataset_name.shellescape}", "Failed to set workspace mountpoint"
          app_volume.mount!
        else
          app_volume.prepare!
        end
        @host.exec! "mkdir -p #{app_build_host_path.shellescape}", "Failed to create app directory"

        comment_sub_step "Transfer source to build host"
        transfer_source
      end

      # rsync the local checkout into the app volume on the build host. bundle/
      # node_modules/assets are excluded here and rebuilt natively in the chroot.
      def transfer_source
        excludes = APP_TRANSFER_EXCLUDES.map { |e| "--exclude=#{e.shellescape}" } * ' '
        ssh = "ssh -i #{CloudModel.config.ssh_key_file.shellescape} -o StrictHostKeyChecking=no"
        local_exec! "rsync -a --delete #{excludes} -e #{ssh.shellescape} #{@web_image.build_path.shellescape}/ root@#{@host.ssh_address}:#{app_build_host_path.shellescape}/",
          "Failed to transfer source to build host"
      end

      # The build system is the shared build-env (Ruby/Rust/Clang) — make sure the
      # extra build tooling the pipeline needs is present.
      def install_build_prerequisites
        comment_sub_step "Install build prerequisites (git, node 22)"
        # Debian bookworm ships node 18, too old for the app's toolchain
        # (puppeteer/vite want node >= 22). Pull node 22 from NodeSource; it
        # brings a matching npm. (With the persistent build chroot this runs
        # once, not per build.)
        chroot! buildsys_volume.rootfs_path, [
          "apt-get update",
          "apt-get install -y git curl ca-certificates gnupg",
          "curl -fsSL https://deb.nodesource.com/setup_22.x | bash -",
          "apt-get install -y nodejs"
        ] * ' && ', "Failed to install build prerequisites"
      end

      # Copies the git deploy key into the throwaway build system so
      # `bundle install` can clone private git-source gems. The key lands only
      # in this build system, which is destroyed right after the build. github
      # host verification is disabled here (no persistent known_hosts to seed).
      def configure_git_credentials
        key = CloudModel.config.git_ssh_key_file
        return unless key && File.file?(key)

        comment_sub_step "Install git deploy key into build system"
        ssh_dir = "#{buildsys_volume.rootfs_path}/root/.ssh"
        @host.exec! "mkdir -p #{ssh_dir.shellescape} && chmod 700 #{ssh_dir.shellescape}", "Failed to create .ssh in build system"
        @host.sftp.file.open("#{ssh_dir}/id_git", 'w', 0600) { |f| f.write File.read(key) }
        @host.sftp.file.open("#{ssh_dir}/config", 'w', 0600) do |f|
          f.write "Host github.com\n  User git\n  IdentityFile /root/.ssh/id_git\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n"
        end
      end

      def bundle_image
        return true unless File.file? "#{@web_image.build_path}/Gemfile"

        comment_sub_step "Bundle install"
        # Configure bundler via ENV rather than `bundle config set --local`,
        # which refuses to non-interactively overwrite the values the app ships
        # in its own .bundle/config ("You are replacing the current local value
        # of without…"). ENV cleanly overrides those. GIT_SSH_COMMAND forces the
        # git-source gem clones onto the injected deploy key.
        chroot! buildsys_volume.rootfs_path, [
          "cd #{CHROOT_APP_ROOT}",
          "export #{GIT_SSH_COMMAND}",
          # Point rustup/cargo at the toolchain the template installed (with its
          # default set) — without RUSTUP_HOME/CARGO_HOME rustup looks in root's
          # empty ~/.rustup and fails ("could not choose a version of cargo").
          # Needed for Rust-native gems.
          "export CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup PATH=\"/usr/local/cargo/bin:$PATH\"",
          # BUNDLE_JOBS=1 (in BUNDLE_ENV): serialize install so bundler doesn't
          # unshallow the same git repo (referenced by several gems) from
          # parallel workers, which races on git's shallow.lock.
          "export #{BUNDLE_ENV}",
          "bundle install",
          "bundle clean --force"
        ] * ' && ', "Unable to bundle image"
      end

      # The artifact's native gems are compiled against the ruby the guest
      # template ships, so it must also RUN on that ruby. The app's own
      # .ruby-version may pin a different patch level (e.g. 3.4.8) that is not
      # installed in the template — RVM/Passenger then refuse to boot
      # ("Required ruby-3.4.8 is not installed"). Overwrite it with the
      # template's actual RUBY_VERSION so the runtime picks the matching (and
      # ABI-compatible) interpreter.
      def pin_ruby_version
        return true unless File.file? "#{@web_image.build_path}/Gemfile"

        if (rv = @web_image.ruby_version).present?
          # The web image declares its Ruby — the single source of truth (the
          # Nginx/Passenger service must install this exact version at runtime).
          comment_sub_step "Pin .ruby-version to WebImage.ruby_version (#{rv})"
          @host.exec! "printf %s #{rv.shellescape} > #{app_build_host_path.shellescape}/.ruby-version",
            "Unable to pin ruby version"
        else
          # Fall back to whatever Ruby the build environment provides.
          comment_sub_step "Pin .ruby-version to the build environment's ruby"
          chroot! buildsys_volume.rootfs_path,
            "cd #{CHROOT_APP_ROOT} && ruby -e 'print RUBY_VERSION' > .ruby-version",
            "Unable to pin ruby version"
        end
      end

      # Persists bundler's deployment settings into the artifact's own
      # .bundle/config. During build the BUNDLE_* settings are ENV-only, so the
      # gems (including git-source ones like carrierwave-mongoid) land in the
      # app-local ./bundle — but Passenger boots with the system RVM gem home
      # and, without this file, has no idea to look there. It then raises
      # Bundler::PathError for the git gems and the app cannot spawn. Writing
      # BUNDLE_PATH=bundle (relative to the Rails root, wherever the release is
      # mounted) makes the runtime bundler resolve against the bundled gems.
      def write_bundle_config
        return true unless File.file? "#{@web_image.build_path}/Gemfile"

        comment_sub_step "Persist bundler config (.bundle/config)"
        @host.exec! "mkdir -p #{app_build_host_path.shellescape}/.bundle", "Failed to create .bundle dir"
        @host.sftp.file.open("#{app_build_host_path}/.bundle/config", 'w', 0644) do |f|
          f.write "---\n" \
            "BUNDLE_PATH: \"bundle\"\n" \
            "BUNDLE_DEPLOYMENT: \"true\"\n" \
            "BUNDLE_WITHOUT: \"development:test\"\n"
        end
      end

      # Pins puppeteer's browser cache INSIDE the app (relative to the config's
      # own dir), so `yarn install` downloads the arch-correct Chromium into the
      # artifact and grover/puppeteer find it at runtime wherever the release is
      # mounted — puppeteer's default (~/.cache/puppeteer) would land outside the
      # artifact and be lost. Skipped if the app ships its own puppeteer config.
      def write_puppeteer_config
        path = "#{app_build_host_path}/.puppeteerrc.cjs"
        return if @host.exec("test -e #{path.shellescape}").first

        comment_sub_step "Pin Chromium cache into app (.puppeteerrc.cjs)"
        @host.sftp.file.open(path, 'w', 0644) do |f|
          f.write "const { join } = require('path');\nmodule.exports = { cacheDirectory: join(__dirname, '.cache', 'puppeteer') };\n"
        end
      end

      def yarn_install
        return true unless File.file? "#{@web_image.build_path}/package.json"

        write_puppeteer_config

        comment_sub_step "Yarn install"
        # Full install (no --production): the Vite/Sass asset toolchain lives in
        # devDependencies and is needed to build assets. Skip Playwright's
        # browser download — it is a test-only devDependency and its browsers
        # would land in ~/.cache (outside the artifact), wasting build time.
        chroot! buildsys_volume.rootfs_path, [
          "cd #{CHROOT_APP_ROOT}",
          "export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1",
          "command -v yarn >/dev/null 2>&1 || npm install -g yarn",
          "yarn install --non-interactive"
        ] * ' && ', "Unable to install yarn packages"
      end

      def build_assets
        comment_sub_step "Build assets"
        # BUNDLE_ENV so `bundle exec` finds the gems in ./bundle (incl. git-source
        # ones). SECRET_KEY_BASE: a throwaway value just so the app can boot to
        # compile assets (Rails requires one in production even when the real key
        # comes from credentials/ENV at runtime). Never used at runtime.
        chroot! buildsys_volume.rootfs_path, "cd #{CHROOT_APP_ROOT} && export #{BUNDLE_ENV} && SECRET_KEY_BASE=assets_build RAILS_ENV=production RAILS_GROUPS=assets bundle exec rake assets:precompile", "Unable to build assets"
      end

      def finalize_app_volume
        comment_sub_step "Set ownership"
        # Container 'www' runs as uid 1001; unprivileged LXD maps that to host
        # 101001. Owning the workspace as 101001 lets the deploy clone attach
        # without id-shifting and Passenger read/write immediately.
        @host.exec! "chown -R 101001:101001 #{app_build_host_path.shellescape}", "Failed to set app ownership"

        comment_sub_step "Snapshot artifact version"
        cleanup_chroot buildsys_volume.rootfs_path
        app_volume.unmount!
        # Versioned snapshot (never a fixed @ready): a rebuild adds a new @v<ts>
        # and never has to destroy a snapshot a deployed guest still clones from.
        # Build scratch (.git, caches, ext target) stays in the workspace for
        # incremental rebuilds and is stripped from the per-guest deploy clone.
        ts = Time.now.utc.strftime("%Y%m%d%H%M%S")
        @host.exec! "zfs snapshot #{@web_image.build_dataset(@arch).shellescape}@v#{ts}", "Failed to snapshot artifact version"
        @web_image.record_artifact_version @arch, ts

        _success, used = @host.exec "zfs list -H -p -o used #{@web_image.build_dataset(@arch).shellescape}"
        @web_image.record_artifact_size @arch, used.to_s.strip.to_i

        comment_sub_step "Destroy build system (workspace kept)"
        buildsys_volume.destroy!

        prune_old_artifact_versions
      end

      # Prunes superseded artifact versions, keeping the most recent few. ZFS
      # refuses to destroy a snapshot with dependent clones (a deployed guest),
      # so those simply survive until the guest is redeployed/removed.
      def prune_old_artifact_versions(keep: 2)
        ds = @web_image.build_dataset(@arch)
        success, out = @host.exec "zfs list -H -o name -t snapshot -r #{ds.shellescape}"
        return unless success

        versions = out.to_s.split("\n").select { |s| s =~ /@v\d+\z/ }.sort
        (versions[0...-keep] || []).each do |snap|
          @host.exec "zfs destroy #{snap.shellescape}"
        end
      end

      def cleanup_build_env
        cleanup_chroot buildsys_volume.rootfs_path if @buildsys_volume
        # Keep the workspace (persistent, incremental) — only tear down this
        # build's throwaway build system.
        @app_volume&.unmount!
        @buildsys_volume&.destroy!
      rescue Exception => e
        CloudModel.log_exception e
      end

      # ---- volumes / paths ----

      # Throwaway CoW clone of the guest template — the chroot the app is built
      # in. Sits next to the app dataset (…-buildenv).
      def buildsys_volume
        @buildsys_volume ||= CloudModel::BuildZfsVolume.new @host,
          "#{@web_image.build_dataset(@arch)}-buildenv",
          mountpoint: "#{@web_image.build_mountpoint(@arch)}-buildenv"
      end

      # The deployable app artifact, mounted inside the build system at the
      # CHROOT_APP_ROOT staging path so the chroot build writes straight into
      # it. Its dataset root is the Rails root — deploy clones and mounts it as
      # a release.
      def app_volume
        @app_volume ||= CloudModel::BuildZfsVolume.new @host,
          @web_image.build_dataset(@arch),
          mountpoint: "#{buildsys_volume.rootfs_path}#{CHROOT_APP_ROOT}",
          compression: CloudModel.config.zfs_compression
      end

      # Host path to the Rails app root inside the build system.
      def app_build_host_path
        "#{buildsys_volume.rootfs_path}#{CHROOT_APP_ROOT}"
      end

      # ---- redeploy orchestration (rolls the built artifact out per service) ----

      def redeploy(options = {})
        unless @web_image.redeploy_state == :pending or options[:force]
          puts "Redeploy WebImage #{@web_image.name} failed, as it is not pending for redeploy: #{@web_image.redeploy_state}"
          return false
        end
        @web_image.update_attributes redeploy_state: :running, redeploy_last_issue: nil
        @web_image.append_to_build_log "\n$ Rollout\n"
        puts "Redeploy WebImage #{@web_image.name}"
        begin
          services = @web_image.services

          services.each do |service|
            if service.redeployable? or options[:force]
              service.update_attributes redeploy_web_image_state: :pending
            end
          end
          services.each do |service|
            service.redeploy! options
          end
        rescue Exception => e
          CloudModel.log_exception e
          @web_image.update_attributes redeploy_state: :failed, redeploy_last_issue: "#{e}"
          return false
        end
        @web_image.append_to_build_log "Rollout finished\n"
        @web_image.update_attributes redeploy_state: :finished
      end

      # ---- logging ----

      # Runs the block with the worker's stdout teed into the web image's build
      # log, buffered and flushed at most once a second so a chatty native build
      # doesn't hammer Mongo (each flush pokes the `web_images` change-stream →
      # WebSocket push to the admin console).
      def with_build_log(&block)
        buffer = +''
        last_flush = Time.now
        flush = lambda do
          return if buffer.empty?
          @web_image.append_to_build_log buffer.dup
          buffer.clear
          last_flush = Time.now
        end

        # Net::SSH hands worker output back as ASCII-8BIT; sanitise to valid
        # UTF-8 before it meets the UTF-8 build log (else concatenating a chunk
        # with high bytes raises Encoding::CompatibilityError).
        CloudModel::StdoutTee.capture ->(text) { buffer << text.to_s.dup.force_encoding(Encoding::UTF_8).scrub('?'); flush.call if Time.now - last_flush >= 1 } do
          begin
            block.call
          ensure
            flush.call
          end
        end
      end

      # Runs a command locally on the admin machine with a bundler-free
      # environment (used for the git checkout).
      def run_with_clean_env step, command
        Bundler.with_original_env do
          ENV.delete_if { |k, _| k[0, 7] == "BUNDLE_" }
          ENV["PATH"] ||= "/usr/bin:/bin:/usr/sbin:/sbin"
          ENV["PATH"] += ':/usr/local/bin'
          ENV["RUBYLIB"] = nil
          if ENV.has_key?("RUBYOPT")
            ENV["RUBYOPT"] = ENV["RUBYOPT"].sub("-rbundler/setup", "")
          end

          run_step step, command
        end
      end

      def run_step step, command
        Rails.logger.debug "### #{step}: #{command}"
        command = "PATH=/bin:#{ENV["PATH"].shellescape} #{command}"
        puts "\n$ #{step}"

        # Stream stdout+stderr line by line. stderr is merged deliberately:
        # build tools (git, bundler) write their actual output to stderr.
        c_out = +''
        IO.popen(command, err: [:child, :out]) do |io|
          io.each_line do |line|
            c_out << line
            print line
          end
        end

        unless $?.success?
          puts "FAILED: #{step} (#{$?})"
          raise ExecutionException.new command, "#{step} failed (#{$?})", c_out
        end
        c_out
      end
    end
  end
end
