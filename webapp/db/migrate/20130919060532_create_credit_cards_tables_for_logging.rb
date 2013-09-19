class CreateCreditCardsTablesForLogging < ActiveRecord::Migration
  def change
    create_table :credit_cards do |t|
      t.integer :customer_object_id, null: false
      t.string  :card_number_hash,   null: false
      t.boolean :deleted,            null: false, default: false
    end
  end
end
