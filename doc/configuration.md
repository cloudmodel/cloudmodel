# CloudModel Configuration Reference

All options are set in the host app's initializer
(`config/initializers/cloud_model_config.rb`) inside a `configure` block:

```ruby
CloudModel.setup do |config|
  config.build_host_name = 'core06'
  config.zfs_compression = 'lz4'
  # …
end
```

Every option has a sensible default (shown below); set only what you need to
override. Values may differ per Rails environment — the initializer typically
branches on `Rails.env`.

---

## Paths & directories

| Option | Default | Purpose |
|---|---|---|
| `data_directory` | `#{Rails.root}/data` | Base for keys, build workspaces, backups. A Capistrano linked/shared dir. |
| `backup_directory` | `#{data_directory}/backups` | Where local backups are written. |

## Build volumes (ZFS)

| Option | Default | Values | Purpose |
|---|---|---|---|
| `build_dataset` | `guests/build` | ZFS dataset path | Parent dataset that guest/core templates **and** web-image artifacts are built under. Must be in the same pool as the LXD container datasets so deploys can `zfs clone`. |
| `build_host_name` | *(none)* | String **or** per-arch Hash | The host(s) templates and web images are built on. A String (`'core06'`) builds everything there; a Hash (`{ 'arm64' => 'host23', 'amd64' => 'host24' }`) picks a build host per architecture. An arch without an entry builds on the deploy target host itself. |
| `bundle_command` | `/usr/local/rvm/bin/rvm default do bundle` | shell command | How bundler is invoked on the admin machine (git checkout only). Dev typically sets `'bundle'`. |
| `ruby_version` | `3.4` | version string | Ruby version used by build components. |
| `php_version` | `8.4` | version string | PHP major installed by the PHP components (from the ondrej/php PPA on Ubuntu, packages.sury.org on Debian). |

### `zfs_compression`

Compression applied to **build volumes** — guest/core templates **and**
web-image artifacts (and their deploy clones). Default **`lz4`**.

| Value | Ratio (typ.) | CPU | Portability | When to use |
|---|---|---|---|---|
| `lz4` *(default)* | ~2.35× | near-free (multi-GB/s, early-abort on incompressible data) | **every** OpenZFS (since 0.6.5, ~2015) | The safe default. Smaller datasets + less I/O usually make it net-neutral-to-faster; the only write cost is once, at build time. |
| `zstd` | ~3.2× (≈ old tar.bz2) | noticeable on write, cheap on read | needs **OpenZFS ≥ 2.0** on every host it is `zfs send`-ed to | Only when the *whole* cloud runs OpenZFS ≥ 2.0. Older hosts reject the `compression=zstd` property on receive. |
| `off` | 1× | none | everywhere | Max build/deploy speed, but ~2.35× more disk and I/O. |

Notes:
- Not the same as the `zstd` apt package — ZFS zstd lives in the OpenZFS kernel
  module (≥ 2.0), not userspace; `apt install zstd` does **not** enable it.
- The cross-host transfer is compressed independently via `ssh -C`, regardless
  of the on-disk setting.
- CoW means many guest clones of one artifact share its (compressed) blocks, so
  compression compounds on deploy hosts.

## SSH & keys

| Option | Default | Purpose |
|---|---|---|
| `ssh_key_file` | `#{data_directory}/keys/id_rsa` | SSH private key the controller uses to reach hosts as `root`. |
| `zfs_sync_key_file` | `#{data_directory}/keys/zfs_sync` | Private key of the host-to-host ZFS sync pair (public key beside it as `.pub`). Nothing to prepare by hand: the pair is generated when first needed, and the first sync between two hosts pushes it to them (private key, forced-command wrapper `zfs-receive-only`, restricted `authorized_keys` entry); `rake cloudmodel:host:deploy_zfs_sync_key` rolls it out ahead of time. Build volumes stream directly between two hosts that both have it; a host that cannot be prepared keeps the route through the controller. |
| `git_ssh_key_file` | `~/.ssh/id_rsa` | **Unencrypted** deploy key that can read the private git-source gems in a WebImage's `Gemfile`. Copied into the throwaway build chroot for `bundle install`, then destroyed with it. Point it at a dedicated read-only key (e.g. `data/keys/git_deploy`); an agent-encrypted key cannot be used. |

## OS image builds

| Option | Default | Purpose |
|---|---|---|
| `ubuntu_mirror` | `http://archive.ubuntu.com/ubuntu/` | apt mirror for Ubuntu base images. |
| `ubuntu_deb_src` | `true` | Enable `deb-src` lines in Ubuntu sources. |
| `ubuntu_version` | `22.04.4` | Default Ubuntu point release (`ubuntu_major_version` derives `22.04`). |
| `debian_version` | `12` | Default Debian release. |
| `unattended_upgrades` | `true` | Install `unattended-upgrades` on hosts and guests, limited to the distribution's security suite, no automatic reboot; hosts additionally never update ZFS or the kernel this way. Installed into templates, re-applied on every host and guest (re)deploy (so templates built before the feature need no rebuild), pushable to running systems with `rake cloudmodel:host:deploy_unattended_upgrades` / `cloudmodel:guest:deploy_unattended_upgrades`. |

## Networking & DNS

| Option | Default | Purpose |
|---|---|---|
| `tinc_network` | `10.42.0.0/16` | VPN subnet for the tinc mesh between hosts/guests. |
| `tinc_client_name` | `cloudmodel` | tinc network name. |
| `dns_servers` | `1.1.1.1 8.8.8.8 9.9.9.10` | Resolvers configured in guests. |
| `dns_domains` | `[]` | Managed DNS domains. |
| `use_external_ip` | `false` | Use hosts' external IPs instead of the VPN — handy for a dev box without tinc. |
| `host_mac_address_prefix_init` | `00:00` | Prefix seed for generated guest MAC addresses. |
| `additional_hosts` | `{}` | Static name → address map for split-horizon setups (e.g. a development cluster that mirrors production hostnames: `{'app.example.com' => '10.0.0.5'}`). Not rendered into guests by cloudmodel itself; consumed by dev tooling such as cloudmodel-api-qemu's `dev:net` DNS forwarder. |

## Backups

| Option | Default | Purpose |
|---|---|---|
| `backup_concurrency` | `4` | Max backups run concurrently in `backup_all`. Keep ≤ the Mongoid pool size (each backup uses a connection). |
| `backup_hosts` | `[]` | Hosts that receive pull-based ZFS backups. |
| `backup_snapshot_prefix` | `cm-bkp-` | Prefix for the ZFS backup snapshots (`<dataset>@<prefix><timestamp>`). The pruner and incremental-base lookup key on it — set it to match any pre-existing snapshots. |
| `skip_sync_images` | `false` | If true, do **not** sync build volumes between hosts on deploy (build volume must already be present on the target). |

## Monitoring

| Option | Default | Purpose |
|---|---|---|
| `monitoring_notifiers` | `[]` | Notifier objects alerted on monitoring issues (e.g. log / Slack notifiers). |
| `monitoring_sample_retention` | `{ raw: 2.days, hour: 90.days, day: 3.years }` | Retention window per sample resolution; older samples expire via a MongoDB TTL index. Override the whole hash. |
| `issue_url` | *(none)* | URL template for item-issue links (`%id%` placeholder). |

## Jobs & mail

| Option | Default | Purpose |
|---|---|---|
| `job_queue` | `:default` | Delayed::Job queue name for enqueued deploy/build/backup jobs. |
| `admin_email` | *(none)* | Admin contact address. |
| `email_domain` | *(none)* | Default mail domain. |

## Cloud API providers (`config.api.*`)

The `config.api.*` namespace is populated by the optional provider gems, only
where that gem is bundled. Their options are **documented in each gem**, not
here:

- `config.api.hetzner.*` — see [cloudmodel-api-hetzner](https://github.com/cloudmodel/cloudmodel-api-hetzner)
- `config.api.desec.*` — see [cloudmodel-api-desec](https://github.com/cloudmodel/cloudmodel-api-desec)
- `config.api.qemu.*` — see [cloudmodel-api-qemu](https://github.com/cloudmodel/cloudmodel-api-qemu)

(These configure provider credentials and provisioning parameters — never
commit real secrets.)
