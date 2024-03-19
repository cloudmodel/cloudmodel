module CloudModel
  module Workers
    module Components
      class JitsiComponentWorker < BaseComponentWorker
        def build build_path
          puts "Prepare prosody"
          chroot! build_path, "curl -sL https://prosody.im/files/prosody-debian-packages.key -o /etc/apt/keyrings/prosody-debian-packages.key", "Failed to add prosody key"
          chroot! build_path, "echo \"deb [signed-by=/etc/apt/keyrings/prosody-debian-packages.key] http://packages.prosody.im/debian $(lsb_release -sc) main\" | tee /etc/apt/sources.list.d/prosody-debian-packages.list", "Failed to add prosody source"



          puts "Prepare jitsi"
          chroot! build_path, "curl -sL https://download.jitsi.org/jitsi-key.gpg.key | sh -c 'gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg'", "Failed to add jitsi key"
          chroot! build_path, "echo \"deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/\" | tee /etc/apt/sources.list.d/jitsi-stable.list", "Failed to add jitsi source"

          puts "update apt"
          chroot! build_path, "apt-get update", "Failed to update packages"

          puts "install lua"
          chroot! build_path, "apt-get install lua5.2 -y", "Failed to install lua 5.2"

          puts "install dependencies"
          #chroot! build_path, "apt-get install autoconf automake autotools-dev bind9-dnsutils bind9-host bind9-libs binutils bzip2 coturn cpp dnsutils file gcc jq libasan6 libatomic1 libbinutils libc-dev-bin libc-devtools libc6-dev libcc1-0 libcrypt-dev libctf-nobfd0 libctf0 libdpkg-perl linux-libc-dev lua-any lua-basexx lua-bit32 lua-cjson lua-expat lua-filesystem lua-inspect lua-luaossl lua-posix lua-readline lua-sec lua-socket lua-unbound luarocks m4 manpages manpages-dev pkg-config prosody rpcsvc-proto ruby-hocon sqlite3 ssl-cert telnet uuid-runtime -y", "Failed to install dependencies"

          # puts "install jitsi"
          # chroot! build_path, "apt-get install jitsi-meet -y", "Failed to install jitsi-meet"

          ## Config auth - https://www.crosstalksolutions.com/how-to-enable-jitsi-server-authentication/

          ## Autostart lobby - https://github.com/shawnchin/prosody-plugins/tree/main/lobby_autostart
          # cd /usr/share/jitsi-meet/prosody-plugins/
          # wget -O mod_lobby_autostart.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/lobby_autostart/mod_lobby_autostart.lua

          puts "done"
        end
      end
    end
  end
end
