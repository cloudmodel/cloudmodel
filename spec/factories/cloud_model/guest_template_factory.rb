Factory.define :guest_template, class: CloudModel::GuestTemplate do |f|
  f.template_type { Factory :guest_template_type }
  f.core_template { Factory :guest_core_template }
end