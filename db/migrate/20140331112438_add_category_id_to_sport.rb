class AddCategoryIdToSport < ActiveRecord::Migration
  def self.up
    add_column :sports, :category_id, :integer
    add_column :sports, :coming_soon, :boolean, :default => true
    add_index :sports, :category_id
    remove_index :sports, :name
    add_index :sports, [:name, :category_id], :unique => true
  end

  def self.down
    remove_column :sports, :category_id
    remove_column :sports, :coming_soon
    add_index :sports, :name
  end
end
