Factory.define :lxd_custom_volume, class: CloudModel::LxdCustomVolume do |f|
  f.guest { Factory :guest }
  f.mount_point { "var/#{Faker::Internet.domain_word}"}
  f.disk_space { rand(1..50) * 1024 * 1024 * 1024 }
  f.writeable { rand(0..1) == 1 }

  f.skip_volume_creation { true }
end