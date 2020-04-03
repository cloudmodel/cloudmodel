Factory.define :certificate, class: CloudModel::Certificate do |f|
  f.name { Faker::Lorem.words(number: 2)  * ' '}
end