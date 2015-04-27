class AddTokenBalanceToUser < ActiveRecord::Migration
  def change
    add_column :users, :token_balance, :integer, :default => 0
    add_column :contest_types, :takes_tokens, :boolean, :default => false
  end
end
