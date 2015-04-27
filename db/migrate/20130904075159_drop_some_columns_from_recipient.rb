class DropSomeColumnsFromRecipient < ActiveRecord::Migration
  def change
    remove_column :recipients, :account_num, :string
    remove_column :recipients, :routing, :string
    remove_column :recipients, :legal_name, :string
  end
end
