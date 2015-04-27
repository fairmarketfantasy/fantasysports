class IndividualPredictionBelongsToRoster < ActiveRecord::Migration
  def change
    rename_column :individual_predictions, :roster_player_id, :roster_id
    add_column :individual_predictions, :player_id, :integer
    add_column :individual_predictions, :user_id, :integer
    remove_column :individual_predictions, :event_type, :string
    remove_column :individual_predictions, :value, :integer
    remove_column :individual_predictions, :less_or_more, :string
  end
end
