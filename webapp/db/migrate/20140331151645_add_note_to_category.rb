class AddNoteToCategory < ActiveRecord::Migration
  def change
    add_column :categories, :note, :string, :default => 'COMING SOON'
  end
end
