Factory.define :volume_group, class: CloudModel::VolumeGroup do |f|
  f.name { Faker::Internet.domain_word }
  f.disk_space { '100 GiB' }
  f.host { Factory :host}
  f.disk_device { 'md0' }
end