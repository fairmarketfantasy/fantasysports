ActiveAdmin.register CustomerObject do
  filter :user_id

  index do
    column :id
    column :balance
    column(:user_email, :sortable => :user_id) { |co| co.user.email }
    column(:monthly_winnings, :sortable => :monthly_winnings) { |co| co.monthly_winnings/100 }
    column(:monthly_entry_charges, :sortable => :monthly_contest_entries) { |co| co.monthly_contest_entries * 10 }
    column(:fanbucks) { |co| co.net_monthly_winnings/100 }
    default_actions
  end
end
