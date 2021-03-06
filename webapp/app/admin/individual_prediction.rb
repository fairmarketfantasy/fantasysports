ActiveAdmin.register IndividualPrediction do
  filter :user_id
  filter :market_id
  filter :player_id

  index do
    column :id
    column :user_id
    column(:user_email) { |ip| ip.user.email }
    column(:market_name) { |ip| ip.market.name }
    column(:player_name) { |ip| ip.player.name }
    column :market_id
    column :player_id
    column :pt
    column :award
    column :created_at
    column(:event_type) { |ip| ip.event_predictions.last.event_type }
    column(:diff) { |ip| ip.event_predictions.last.diff }
    column(:value) { |ip| ip.event_predictions.last.value }
    column :game_result
    column :state
    default_actions
  end
end
