Factory.define :item_issue, class: CloudModel::ItemIssue do |f|
  f.title { Faker::Lorem.words(number: 3) * ' '}
  f.message { Faker::Lorem.words(number: 5) * ' ' }
end