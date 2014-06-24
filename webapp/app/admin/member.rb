ActiveAdmin.register Member, :as => 'Competition_Member' do
  actions :all, except: [:destroy]

  filter :competition

  index do
    column :id
    column(:competition_name) {|m| m.competition.name }
    column(:name) {|m| m.memberable.name if m.memberable }
    column :memberable_type
    column :rank
    actions
  end
end
