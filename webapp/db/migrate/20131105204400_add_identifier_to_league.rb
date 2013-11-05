class AddIdentifierToLeague < ActiveRecord::Migration
  def change
    add_column :leagues, :identifier, :string
  end
end
