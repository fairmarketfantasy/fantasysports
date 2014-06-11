class AddNewFieldsToCategories < ActiveRecord::Migration
  def change
    add_column :categories, :is_active, :boolean, default: true
    add_column :categories, :is_new, :boolean, default: false
    add_column :categories, :title, :string, null: false, default: ''
    add_column :sports, :title, :string, null: false, default: ''
  end
end
