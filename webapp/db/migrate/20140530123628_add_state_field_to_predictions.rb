class AddStateFieldToPredictions < ActiveRecord::Migration
  def change
    add_column :predictions, :state, :string
  end
end
