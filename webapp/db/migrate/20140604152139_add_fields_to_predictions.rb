class AddFieldsToPredictions < ActiveRecord::Migration
  def change
    add_column :predictions, :result, :string
    add_column :predictions, :award,  :decimal
  end
end
