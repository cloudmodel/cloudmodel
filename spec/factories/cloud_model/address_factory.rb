Factory.define :address, class: CloudModel::Address do |f|
  f.ip { Faker::Internet.ip_v4_address }
  f.subnet 24
  f.gateway { |x| x.list_ips.last }
end