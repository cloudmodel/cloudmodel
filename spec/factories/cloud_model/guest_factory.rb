Factory.define :guest, class: CloudModel::Guest do |f|
  f.name { Faker::Internet.domain_word }
  f.host { Factory :host}
  f.root_volume { Factory :logical_volume }
  f.private_address { |g| g.host.dhcp_private_address }
  f.deploy_state_id { 0xff }
end