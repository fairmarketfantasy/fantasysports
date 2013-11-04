class UpdateLeagueBools < ActiveRecord::Migration
  def change
    remove_column :leagues, :takes_tokens, :integer
    add_column :leagues, :takes_tokens, :bool
  end
end
