ActiveAdmin.register StatEvent do

  filter :activity
  filter :game_game_time
  filter :player_name, :as => :string

  index do
    column :activity
    column :player_stats_id
    column :player do |se|
      se.player && se.player.name
    end
    column :game do |se|
      se.game_stats_id
    end
    column :game_detail do |se|
      se.game.teams.map(&:name).join(' AND ') + ' ' + se.game.game_time.getlocal.to_s
    end
    column :quantity
    column :points_per
    column :point_value
    default_actions
  end

end

