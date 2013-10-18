class AddTokensToRosters < ActiveRecord::Migration
  def change
    add_column :rosters,:takes_tokens, :boolean
  end
end
