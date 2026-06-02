Factory.define :host, class: CloudModel::Host do |f|
  # name has a global uniqueness validation; Faker's word pool is small enough
  # to collide across a full suite run, so append a unique suffix.
  f.name { "#{Faker::Internet.domain_word}-#{SecureRandom.hex(4)}" }
  f.tinc_public_key {}
  f.primary_address { Factory.build(:address) }
  f.private_network { Factory.build(:address) }
end