ActiveAdmin.register Prediction, :as => "FWCUP_Prediction" do
  actions :all, except: [:destroy]
  filter :user_id
  filter :prediction_type

  index do
    column :id
    column :user_id
    column(:user_email) { |p| p.user.email }
    column(:game) do |p|
     "#{Team.find(p.game.home_team).name} @ #{Team.find(p.game.away_team).name}" if p.game
    end

    column(:game_time) do |p|
      p.game.game_time.utc if p.game
    end

    column(:player_name) do |p|
      Player.where(id: p.stats_id).first.name if p.prediction_type == 'mvp'
    end

    column(:team_name) do |p|
      if ['win_the_cup', 'win_groups', 'daily_wins'].include?(p.prediction_type)
        Team.where(stats_id: p.stats_id).first.name
      end
    end

    column :prediction_type
    column :pt
    column :created_at
    column :state
    column :result
    column :award
    default_actions
  end
end
