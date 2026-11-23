require 'spec_helper'
require 'tmpdir'
require 'open3'

# The shim is plain /bin/sh and runs on the admin too — a fake /opt/ruby
# with "releases" whose bin/ruby reports what it was given is enough to
# exercise the resolution rules end to end.
describe 'cloud_model/support/ruby/shim.sh' do
  let(:shim_source) { File.read File.expand_path('../../../../../app/views/cloud_model/support/ruby/shim_sh.erb', __dir__) }

  around do |example|
    Dir.mktmpdir('ruby-shim') do |dir|
      @dir = dir
      @root = "#{dir}/opt"
      @gems = "#{dir}/gems"
      %w(3.4.11 3.4.13 4.0.1).each do |version|
        bin = "#{@root}/ruby-#{version}/bin"
        FileUtils.mkdir_p bin
        File.write "#{bin}/ruby", "#!/bin/sh\necho \"ruby #{version} GEM_HOME=$GEM_HOME args=$*\"\n"
        File.write "#{bin}/gem", "#!/bin/sh\necho \"gem #{version}\"\n"
        FileUtils.chmod 0755, ["#{bin}/ruby", "#{bin}/gem"]
      end
      FileUtils.mkdir_p "#{@gems}/3.4.0"
      shims = "#{dir}/shims"
      FileUtils.mkdir_p shims
      File.write "#{shims}/.shim", shim_source
      FileUtils.chmod 0755, "#{shims}/.shim"
      %w(ruby gem rake).each { |p| File.symlink "#{shims}/.shim", "#{shims}/#{p}" }
      @shims = shims
      example.run
    end
  end

  def run program, cwd: @dir, env: {}, args: []
    out, err, status = Open3.capture3({ 'RUBY_SHIM_ROOT' => @root, 'RUBY_SHIM_GEM_ROOT' => @gems, 'HOME' => @dir, 'RUBY_VERSION' => nil }.merge(env), "#{@shims}/#{program}", *args, chdir: cwd)
    [out.strip, err.strip, status.exitstatus]
  end

  it 'runs the default line\'s newest release from /etc/ruby-version-like fallback when nothing else says so' do
    # no .ruby-version anywhere, no RUBY_VERSION, no /etc/ruby-version in the test box: the newest of all is not chosen blindly
    out, err, status = run 'ruby'
    expect(status).to eq 127
    expect(err).to include 'no Ruby installed'
    expect(out).to eq ''
  end

  it 'picks the release of the nearest .ruby-version upwards and resolves a line to its newest release' do
    app = "#{@dir}/app/sub"
    FileUtils.mkdir_p app
    File.write "#{@dir}/app/.ruby-version", "3.4\n"
    out, _err, status = run 'ruby', cwd: app, args: %w(-e 1)
    expect(status).to eq 0
    expect(out).to eq "ruby 3.4.13 GEM_HOME=#{@gems}/3.4.0 args=-e 1"
  end

  it 'honours a pinned release that is installed, strips a ruby- prefix' do
    File.write "#{@dir}/.ruby-version", "ruby-3.4.11\n"
    out, _err, _status = run 'ruby'
    expect(out).to start_with 'ruby 3.4.11 '
  end

  it 'falls back from a pinned release that is not installed to the newest of its line, and says so' do
    File.write "#{@dir}/.ruby-version", "3.4.8\n"
    out, err, status = run 'gem'
    expect(status).to eq 0
    expect(out).to eq 'gem 3.4.13'
    expect(err).to eq 'ruby shim: 3.4.8 is not installed, using ruby-3.4.13'
  end

  it 'lets RUBY_VERSION in the environment win and uses a gem home under HOME when the line\'s is not writable' do
    File.write "#{@dir}/.ruby-version", "3.4\n"
    out, _err, _status = run 'ruby', env: { 'RUBY_VERSION' => '4.0' }
    expect(out).to eq "ruby 4.0.1 GEM_HOME=#{@dir}/.gem/ruby/4.0.0 args="
  end

  it 'fails with the installed releases when the wanted line is missing' do
    File.write "#{@dir}/.ruby-version", "3.3\n"
    _out, err, status = run 'ruby'
    expect(status).to eq 127
    expect(err).to include 'no Ruby 3.3 installed'
    expect(err).to include 'ruby-3.4.11 ruby-3.4.13 ruby-4.0.1'
  end

  it 'fails for a program the release does not have' do
    File.write "#{@dir}/.ruby-version", "3.4\n"
    _out, err, status = run 'rake'
    expect(status).to eq 127
    expect(err).to include 'rake is neither in ruby-3.4.13 nor in'
  end
end
