Factory.define :host, class: CloudModel::Host do |f|
  f.name { Faker::Internet.domain_word }
  f.tinc_public_key {}
  f.primary_address { Factory.build(:address) }
  f.private_network { Factory.build(:address) }
end