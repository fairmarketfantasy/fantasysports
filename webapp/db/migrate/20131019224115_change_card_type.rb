class ChangeCardType < ActiveRecord::Migration
  def change
    rename_column :credit_cards, :type, :card_type
  end
end
