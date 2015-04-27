ActiveAdmin.register Promo do
  actions :all, except: [:destroy]
  filter :code
  filter :valid_until

  index do
    column :id
    column :code
    column :valid_until
    column :cents
    column :tokens
    column :only_new_users
    column :created_at

    #column('number_of_uses') {|promo| promo.users.count }
    default_actions
  end

end

