require 'net/ftp'

module CloudModel
  module Workers
    module Components
      class FusekiComponentWorker < BaseComponentWorker
        def build build_path
          ftp_host = 'ftp.halifax.rwth-aachen.de'

          ftp = Net::FTP.new(ftp_host)
          ftp.login
          files = ftp.chdir('apache/jena/binaries/')
          files = ftp.list('apache-jena-fuseki-*.tar.gz')
          latest_fuseki = files.map{|l| l.split(' ').last}.sort{|a,b| b<=>a}.first
          fuseki_url = "ftp://#{ftp_host}#{ftp.pwd}/#{latest_fuseki}"
          ftp.close

          chroot! build_path, "cd /opt && wget -q #{fuseki_url.shellescape} && tar xzf #{latest_fuseki.shellescape} && mv #{latest_fuseki.gsub(/.tar.gz$/, '').shellescape} fuseki && rm #{latest_fuseki.shellescape}", "Failed to download fuseki"

          # todo: render systemd unit

          #chroot! build_path, "apt-get install lsof -y", "Failed to install lsof"
          chroot! build_path, "useradd fuseki -d /var/lib/fuseki -m -r -k /dev/null -c 'Fuseki User'", "Failed to add user fuseki"
        end
      end
    end
  end
end