Factory.define :lxd_custom_volume, class: CloudModel::LxdCustomVolume do |f|
  f.guest { Factory :guest }
  f.mount_point { "var/#{Faker::Internet.domain_word}"}
  
  f.skip_volume_creation { true }
end