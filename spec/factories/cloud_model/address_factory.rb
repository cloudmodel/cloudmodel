Factory.define :address, class: CloudModel::Address do |f|
  f.ip { Faker::Internet.ip_v4_address }
  f.subnet 24
  f.gateway { |x| x.gateway }
end