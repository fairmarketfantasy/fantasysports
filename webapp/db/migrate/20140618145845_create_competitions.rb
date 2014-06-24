class CreateCompetitions < ActiveRecord::Migration
  def change
    create_table :competitions do |t|
      t.integer :sport_id
      t.integer :category_id
      t.string :name
      t.string :state, default: 'in_progress'
      t.references :memberable, polymorphic: true

      t.timestamps
    end
  end
end
