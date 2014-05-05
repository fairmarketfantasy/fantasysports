ActiveAdmin.register IndividualPrediction do
  filter :user_id
  filter :market_id
  filter :player_id

  index do
    column :id
    column :user_id
    column :market_id
    column :player_id
    column :pt
    column :award
    column :created_at
    column(:event_type) { |ip| ip.event_predictions.last.event_type }
    column(:diff) { |ip| ip.event_predictions.last.diff }
    column(:value) { |ip| ip.event_predictions.last.value }
    default_actions
  end
end
