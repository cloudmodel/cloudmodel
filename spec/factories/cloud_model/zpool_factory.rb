Factory.define :zpool, class: CloudModel::Zpool do |f|
  f.name { Faker::Lorem.words(number: 1) }
  f.init_string { Faker::Lorem.words(number: 3) * ' '}
end