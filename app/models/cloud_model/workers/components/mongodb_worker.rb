module CloudModel
  module Workers
    module Components
      class MongodbWorker < BaseWorker
        def build build_path
          chroot! build_path, "apt-get install libreadline5 mongodb -y", "Failed to install mongodb"
        end
      end
    end
  end
end