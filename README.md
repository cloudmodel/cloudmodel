CloudModel
==========

![RSpec](https://github.com/cloudmodel/cloudmodel/workflows/RSpec/badge.svg)
![CodeQL](https://github.com/cloudmodel/cloudmodel/workflows/CodeQL/badge.svg)

CloudModel is a Ruby on Rails engine gem that provides ActiveModel representations for cloud infrastructure management. It models physical/virtual **hosts**, LXD **guests** (containers), **services** running inside containers, reusable software **components**, and **templates** — and ships workers that deploy and configure all of them over SSH.

> As of v0.3.0, Rails 7.2 is required.

Table of Contents
-----------------

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Core Concepts](#core-concepts)
  - [Hosts](#hosts)
  - [Guests](#guests)
  - [Services](#services)
  - [Components](#components)
  - [Templates](#templates)
- [Deployment](#deployment)
- [Monitoring](#monitoring)
- [Rake Tasks](#rake-tasks)
- [Development & Testing](#development--testing)

Requirements
------------

| Dependency | Version |
| --- | --- |
| Ruby | >= 3.2 |
| Rails | ~> 7.2 |
| MongoDB | >= 5.0 |
| Mongoid | >= 7.1.2 |

Installation
------------

Add to your application's `Gemfile`:

```ruby
gem 'cloudmodel'
```

Then run:

```bash
bundle install
```

Mount the engine in `config/routes.rb` if you need the UI:

```ruby
mount CloudModel::Engine, at: '/cloud'
```

Configuration
-------------

Create an initializer (e.g. `config/initializers/cloudmodel.rb`):

```ruby
CloudModel.configure do |config|
  # Email settings
  config.admin_email   = 'admin@example.com'
  config.email_domain  = 'example.com'

  # Default OS / software versions used when building templates
  config.ubuntu_version = '22.04.4'   # default: '22.04.4'
  config.debian_version = '12'        # default: '12'
  config.php_version    = '8.2'       # default: '8.2'
  config.ruby_version   = '3.4'       # default: '3.4'

  # Ubuntu apt mirror
  config.ubuntu_mirror   = 'http://archive.ubuntu.com/ubuntu/'
  config.ubuntu_deb_src  = true        # include deb-src lines

  # DNS
  config.dns_servers  = %w[1.1.1.1 8.8.8.8 9.9.9.10]
  config.dns_domains  = []

  # Local data storage (SSH keys, downloaded images, backups)
  config.data_directory   = "#{Rails.root}/data"         # default
  config.backup_directory = "#{Rails.root}/data/backups" # default

  # VPN / network
  config.tinc_network     = '10.42.0.0/16'   # private overlay network CIDR
  config.tinc_client_name = 'cloudmodel'
  config.use_external_ip  = false             # connect via VPN by default

  # Host MAC address prefix seed (two hex bytes, e.g. '00:00')
  config.host_mac_address_prefix_init = '00:00'

  # ActiveJob queue for async deploy/build jobs
  config.job_queue = :default

  # Hosts available as backup targets
  config.backup_hosts = []

  # Monitoring notifier instances (see Monitoring section)
  config.monitoring_notifiers = []

  # Skip syncing cloud images on deploy (useful in dev)
  config.skip_sync_images = false

  # Bundle command on guests (adjust if not using RVM)
  config.bundle_command = '/usr/local/rvm/bin/rvm default do bundle'
end
```

CloudModel connects to hosts over SSH using a key stored at `{data_directory}/keys/id_rsa`. Generate it once and distribute the public key to all managed hosts.

Core Concepts
-------------

### Hosts

A `CloudModel::Host` represents a physical or virtual server running Ubuntu/Debian with LXD and ZFS.

```ruby
host = CloudModel::Host.create!(
  name:            'node-01',            # lowercase alphanumeric + hyphens/underscores
  primary_address: '203.0.113.10/24',    # public IP in CIDR notation
  private_network: '10.42.1.0/24',       # tinc VPN subnet for this host
  system_disks:    ['sda', 'sdb'],       # ZFS mirror disks
)
```

**Key fields**

| Field | Description |
| --- | --- |
| `name` | Unique identifier, used as hostname |
| `primary_address` | Public-facing IP/CIDR |
| `private_network` | VPN subnet — guests receive addresses from this pool |
| `stage` | `:pending`, `:testing`, `:staging`, `:production` |
| `deploy_state` | `:pending`, `:running`, `:booting`, `:finished`, `:failed`, `:not_started` |
| `mac_address_prefix` | Auto-generated two-byte MAC prefix (unique per host) |
| `system_disks` | Disk names for the ZFS pool |
| `extra_zpools` | Additional embedded ZPool documents |

**Executing commands on a host**

```ruby
success, output = host.exec('uname -r')
output = host.exec!('uname -r', 'Failed to get kernel version')  # raises on failure
```

**Address helpers**

```ruby
host.available_private_address_collection   # IPs not yet assigned to guests
host.available_external_address_collection  # public IPs not yet assigned to guests
host.dhcp_private_address                   # next available private IP
```

### Guests

A `CloudModel::Guest` is an LXD container running on a host.

```ruby
guest = host.guests.create!(
  name:         'app-01',
  root_fs_size: '20GB',   # human-readable sizes accepted
  memory_size:  '4GB',
  cpu_count:    4,
  os_version:   'ubuntu-22.04.4',
)
```

Private address and MAC address are assigned automatically on creation.

**Key fields**

| Field | Description |
| --- | --- |
| `name` | Unique per host |
| `private_address` | VPN IP — auto-assigned from host's private network |
| `external_address` | Optional public IP |
| `external_alt_names` | Additional hostnames for TLS SAN |
| `root_fs_size` | Root filesystem size (Integer bytes or `"10GB"` string) |
| `memory_size` | LXD memory limit |
| `cpu_count` | LXD CPU limit |
| `deploy_state` | `:pending`, `:running`, `:booting`, `:finished`, `:failed`, `:not_started` |
| `up_state` | `:started`, `:stopped`, `:booting`, `:start_failed`, `:not_deployed_yet` |

**Persistent volumes**

```ruby
guest.lxd_custom_volumes.create!(
  mount_point: '/var/data',
  disk_space:  '50GB',
  writeable:   true,
  has_backups: true,
)
```

**Executing commands inside a guest**

```ruby
success, output = guest.exec('php --version')
```

Commands run via `lxc exec` on the host, tunnelled through the host SSH connection.

**Lifecycle**

```ruby
guest.start     # start current LXD container
guest.stop      # stop all LXD containers for this guest
guest.deploy    # enqueue async DeployJob
guest.deploy!   # deploy synchronously (blocks)
guest.redeploy  # enqueue async RedeployJob
guest.redeploy! # redeploy synchronously
```

### Services

Services are embedded documents inside a `Guest`. Each service maps to a concrete class under `CloudModel::Services::`.

**Available service types**

| Key | Class | Description |
| --- | --- | --- |
| `:ssh` | `Services::Ssh` | OpenSSH server |
| `:nginx` | `Services::Nginx` | Nginx web server / reverse proxy |
| `:phpfpm` | `Services::Phpfpm` | PHP-FPM process manager |
| `:mongodb` | `Services::Mongodb` | MongoDB database |
| `:redis` | `Services::Redis` | Redis key-value store |
| `:mariadb` | `Services::Mariadb` | MariaDB/MySQL database |
| `:neo4j` | `Services::Neo4j` | Neo4j graph database |
| `:fuseki` | `Services::Fuseki` | Apache Jena Fuseki (RDF/SPARQL) |
| `:solr` | `Services::Solr` | Apache Solr search |
| `:tomcat` | `Services::Tomcat` | Apache Tomcat (WAR apps) |
| `:collabora` | `Services::Collabora` | Collabora Online (LibreOffice) |
| `:jitsi` | `Services::Jitsi` | Jitsi Meet video conferencing |
| `:forgejo` | `Services::Forgejo` | Forgejo Git forge |
| `:rake` | `Services::Rake` | Scheduled Rake task runner |
| `:backup` | `Services::Backup` | Backup service |
| `:monitoring` | `Services::Monitoring` | Monitoring agent |

**Adding a service to a guest**

```ruby
guest.services.create!(
  _type:          'CloudModel::Services::Nginx',
  name:           'web',
  public_service: true,
)
```

**Base service fields** (all services share these)

| Field | Description |
| --- | --- |
| `name` | Human-readable label |
| `public_service` | When `true`, binds to the external address |
| `has_backups` | Enable backups for this service |
| `additional_components` | Extra component symbols (e.g. `[:imagemagick]`) |

**Address resolution**

```ruby
service.private_address   # guest's VPN IP
service.external_address  # guest's public IP (only when public_service: true)
```

### Components

Components represent installable software packages. They are resolved automatically from a guest's services, but can also be specified explicitly via `additional_components`.

Component symbols follow the pattern `name` or `name@version`:

```ruby
:nginx           # latest managed version
:php             # default PHP version (from config)
:'php@8.1'       # explicit PHP 8.1
:'ruby@3.2'      # explicit Ruby 3.2
:'mongodb@6.0'   # explicit MongoDB 6.0
```

**Available components**

`collabora`, `forgejo`, `fuseki`, `imagemagick`, `java`, `jitsi`, `libfcgi`, `mariadb`, `mariadb_client`, `mongodb`, `ms_core_fonts`, `neo4j`, `nginx`, `php`, `php_imagemagick`, `php_imap`, `php_mysql`, `redis`, `ruby`, `solr`, `tomcat`, `wkhtmltopdf`, `xml`, `nextcloud_spreed_signaling`

**Resolving components programmatically**

```ruby
component = CloudModel::Components::BaseComponent.from_sym(:'php@8.2')
component.base_name    # => 'php'
component.version      # => '8.2'
component.human_name   # => 'Php 8.2'
component.requirements # => [:libfcgi]
```

A guest automatically resolves all components it needs:

```ruby
guest.components_needed  # => [:'libfcgi', :'nginx', :'php@8.2', ...]
```

### Templates

Templates are pre-built LXD images for a specific combination of components and OS version. They speed up guest deployment by avoiding repeated software installation.

```
GuestTemplateType  (unique combination of components + OS version)
  └── has_many :guest_templates (versioned builds)
        └── belongs_to :guest_core_template (base Ubuntu/Debian image)
```

Templates are built once per template type and reused across guests with the same component set.

Deployment
----------

### Host deployment

```ruby
host.deploy    # async (via ActiveJob)
host.deploy!   # synchronous

host.redeploy    # async
host.redeploy!   # synchronous
```

`deploy` sets up ZFS pools, installs LXD, configures networking, and prepares the host for running guests.

### Guest deployment

```ruby
guest.deploy    # async
guest.deploy!   # synchronous

guest.redeploy    # async — rebuilds container from template
guest.redeploy!   # synchronous

# Redeploy multiple guests at once
CloudModel::Guest.redeploy([id1, id2, id3])
```

Deploy states transition: `:pending` → `:running` → `:booting` → `:finished` (or `:failed`).

Only guests in `:finished`, `:failed`, or `:not_started` state are deployable (unless `force: true` is passed).

### Firewall

```ruby
host.restart_firewall   # regenerate and apply firewall rules
```

Firewall rules are embedded on the host document:

```ruby
host.firewall_rules.create!(
  source_address: '0.0.0.0/0',
  dest_port:      443,
  protocol:       :tcp,
)
```

Monitoring
----------

CloudModel includes a health-check system based on check_mk. Each `Host` and `Guest` includes the `HasIssues` mixin, which tracks monitoring state.

```ruby
host.state                         # :undefined, :running, or issue severity
host.monitoring_last_check_at      # Time of last check
host.monitoring_last_check_result  # Raw parsed check_mk result hash

host.mem_usage    # => 64.2 (percent)
host.cpu_usage    # => 12.5 (percent)
guest.mem_usage
guest.swap_usage
guest.cpu_usage
```

### Notifiers

Configure notifiers in the initializer:

```ruby
config.monitoring_notifiers = [
  CloudModel::Notifiers::SlackNotifier.new(webhook_url: 'https://...'),
  CloudModel::Notifiers::LogNotifier.new,
]
```

Service checks are implemented in `lib/cloud_model/monitoring/` for SSH, Nginx, MongoDB, Redis, MariaDB, PHP-FPM, Solr, Tomcat, Fuseki, and Forgejo.

Rake Tasks
----------

```bash
# Backup a single guest's services
GUEST_ID=<mongo_id> bundle exec rake cloudmodel:guest:backup

# Backup all guests with backup-enabled services
bundle exec rake cloudmodel:guest:backup_all

# Sync tinc VPN host key files across all hosts
HOST_ID=<mongo_id> bundle exec rake cloudmodel:host:update_tinc_host_files

# Redeploy a Solr image
SOLR_IMAGE_ID=<mongo_id> bundle exec rake cloudmodel:solr_image:redeploy
```

Development & Testing
---------------------

```bash
# Install dependencies
bundle install

# Start MongoDB (required)
docker run -d -p 27017:27017 mongo:latest

# Run the test suite
bundle exec rspec

# Run a single spec
bundle exec rspec spec/models/cloud_model/guest_spec.rb
```

Tests use RSpec with Mongoid-RSpec matchers, Factory Bot, and Timecop. The database is purged before each example — no manual cleanup needed.

Custom matchers:

```ruby
expect(subject).to have_enum(:deploy_state).with_values(finished: 0xf0, ...)
```

CI runs on GitHub Actions (Ruby 3.2, MongoDB 7) on every push and pull request to `master`. CodeQL security scanning runs weekly.
