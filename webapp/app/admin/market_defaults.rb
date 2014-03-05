ActiveAdmin.register MarketDefaults do
  index do
    column :id
    column :sport_id
    column :sport_name do |md|
      md.sport && md.sport.name
    end
    column :single_game_multiplier
    column :multiple_game_multiplier
  end
end

