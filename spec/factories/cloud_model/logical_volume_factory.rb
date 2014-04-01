Factory.define :logical_volume, class: CloudModel::LogicalVolume do |f|
  f.name { Faker::Internet.domain_word }
  f.volume_group { Factory :volume_group }
end