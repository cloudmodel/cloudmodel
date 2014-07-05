CloudModel.configure do |config|
  config.data_directory = Rails.root.join("../../data").to_s
  config.skip_sync_images = true
end