# CloudModel

Open-source Rails engine gem (MIT license) providing ActiveModel representations for cloud infrastructure management. Manages hosts (physical/virtual servers), guests (LXD containers), services, components, and templates.

**This is an open-source project. Do not add `Co-Authored-By` lines to commits.**

## Tech Stack

- **Ruby 3.4.8** / **Rails ~> 8.0** (engine, not a standalone app)
- **MongoDB** via Mongoid (>= 7.1.2)
- **License:** MIT
- **GitHub:** `cloudmodel/cloudmodel`

## Running Tests

```bash
bundle exec rspec                                          # Full suite
bundle exec rspec spec/models/cloud_model/guest_spec.rb    # Single file
```

MongoDB must be running. Tests use `Mongoid.purge!` before each example — no manual DB cleanup needed. There is **no MCP test runner** for this project — run rspec directly.

CI: GitHub Actions (`.github/workflows/rspec.yml`) — push/PR to `master`, Ruby from `.ruby-version`, MongoDB via Docker.

## Project Structure

```
app/models/cloud_model/
  mixins/             # Shared behaviors (ENumFields, HasIssues, AcceptSizeStrings, ...)
  services/           # Embedded service models (Nginx, MongoDB, Redis, SSH, ...)
  components/         # Software component models (Ruby, PHP, Java, Rust, ...)
  workers/            # Business logic executing on remote hosts via SSH
    services/         # Per-service workers (write_config, auto_start)
    components/       # Per-component workers
  web_apps/           # Web app types (Nextcloud, WordPress, ...)
  notifiers/          # Monitoring notifiers (Slack, Log)
  monitoring/         # Health check implementations (in lib/)

app/views/cloud_model/guest/etc/  # ERB templates rendered to remote hosts
spec/                              # RSpec tests
spec/factories/                    # Miniskirt factories (NOT FactoryBot)
spec/support/matchers/             # Custom matchers (enum)
```

## Key Model Relationships

```
Host
└── has_many :guests

Guest (LXD container)
├── belongs_to :host
├── embeds_many :services        # SSH, Nginx, PHP-FPM, MongoDB, Redis, ...
├── embeds_many :lxd_containers
└── embeds_many :lxd_custom_volumes

Services::Base (abstract, embedded in Guest)
└── concrete types registered in Services::Base.service_types

Workers::BaseWorker → HostWorker / GuestWorker
Workers::Services::BaseWorker → per-service workers
Workers::TemplateWorker → HostTemplateWorker / GuestTemplateWorker
```

## Testing Patterns

### Factories (Miniskirt)

Uses **Miniskirt**, not FactoryBot. Syntax: `Factory(:host)` or `Factory.build(:host)`.

### Mongoid Matchers

```ruby
it { expect(subject).to belong_to(:host).of_type CloudModel::Host }
it { expect(subject).to embed_many(:services).of_type CloudModel::Services::Base }
it { expect(subject).to have_field(:name).of_type(String) }
it { expect(subject).to have_enum(:deploy_state).with_values(pending: 0x00, ...) }
```

### Worker Specs — Common Pitfalls

**Embedded relations:** Mongoid embedded models (services embedded in Guest) cannot have doubles assigned via setter (`subject.guest = guest` triggers `.relations`). Use `allow(subject).to receive(:guest).and_return(guest)` instead.

**`$?` is frozen** (Ruby 3.4): Cannot mock `Process::Status`. When testing methods that use backticks + `$?`, stub the backtick to run a real command that sets `$?`:
```ruby
allow(subject).to receive(:`) { `true`; 'expected output' }
```

**`render_to_remote`** translates dots to underscores in template names (via `translate_template_name`). When stubbing `render`, match the original template name (with dots), not the translated name.

**`build_path` trailing slash:** Template workers return paths like `/cloud/build/host/#{id}/` with a trailing slash. String interpolation `"#{build_path}/etc/..."` produces `//` in paths — this is harmless on Unix. Match the double slash in test expectations.

**`model.class` on doubles:** `auto_start` calls `@model.class.model_name.human`. Verified doubles (`double CloudModel::Services::Foo`) return `RSpec::Mocks::Double` for `.class`. Fix: `double('Foo', class: CloudModel::Services::Foo)`.

### Adding Tests for Services

Most service workers follow the same pattern:

1. **`write_config`** — renders templates to the container via `render_to_remote`/`render_to_guest`
2. **`auto_start`** — creates systemd symlink + optional restart drop-in

Stub the standard dependencies in a `before` block:
```ruby
let(:host) { double CloudModel::Host }
let(:guest) { double CloudModel::Guest, host: host, deploy_path: '/var/lib/lxc/test/rootfs' }
let(:lxc) { double CloudModel::LxdContainer, guest: guest, name: 'test-container' }
let(:model) { double 'ServiceModel', class: CloudModel::Services::MyService }
subject { CloudModel::Workers::Services::MyServiceWorker.new lxc, model }

before do
  allow(host).to receive(:exec)
  allow(host).to receive(:exec!)
  allow(host).to receive(:sftp).and_return(double('sftp'))
  allow(subject).to receive(:comment_sub_step)
  allow(subject).to receive(:mkdir_p)
  allow(subject).to receive(:render_to_remote)
end
```

## Patterns & Conventions

### Enum Fields

Custom hex-keyed enum via `CloudModel::Mixins::ENumFields`:

```ruby
enum_field :deploy_state, {
  0x00 => :pending,
  0x01 => :running,
  0xf0 => :finished,
  0xf1 => :failed,
  0xff => :not_started
}, default: :not_started
```

### Workers

Workers execute on remote hosts via Net::SSH/SFTP. They render ERB templates and push them over SSH:

```ruby
class MyServiceWorker < CloudModel::Workers::Services::BaseWorker
  def write_config
    render_to_remote('cloud_model/guest/etc/my_service/config',
                     '/etc/my_service/config', 0644, guest: @guest, model: @model)
  end
end
```

### Adding a New Service

1. Model: `app/models/cloud_model/services/my_service.rb` extending `Services::Base`
2. Register in `Services::Base.service_types`
3. Worker: `app/models/cloud_model/workers/services/my_service_worker.rb`
4. Templates: `app/views/cloud_model/guest/etc/my_service/`
5. Spec: `spec/models/cloud_model/services/my_service_spec.rb`
6. Worker spec: `spec/models/cloud_model/workers/services/my_service_worker_spec.rb`

### Configuration

```ruby
CloudModel.configure do |config|
  config.admin_email      = 'admin@example.com'
  config.ubuntu_version   = '22.04.4'
  config.php_version      = '8.1'
  config.ruby_version     = '3.1'
  config.dns_servers      = %w[1.1.1.1 8.8.8.8]
  config.data_directory   = "#{Rails.root}/data"
end
```

## Rake Tasks

```bash
GUEST_ID=<id> bundle exec rake cloudmodel:guest:backup
bundle exec rake cloudmodel:guest:backup_all
HOST_ID=<id>  bundle exec rake cloudmodel:host:update_tinc_host_files
SOLR_IMAGE_ID=<id> bundle exec rake cloudmodel:solr_image:redeploy
```
