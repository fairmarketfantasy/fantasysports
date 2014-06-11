class CreateGameRosters < ActiveRecord::Migration
  def change
    create_table :game_rosters do |t|
      t.integer :owner_id, null: false
      t.integer :game_id
      t.integer  :contest_id
      t.integer  :score
      t.integer  :contest_rank
      t.decimal  :amount_paid
      t.datetime :paid_at
      t.string   :cancelled_cause
      t.datetime :cancelled_at
      t.string   :state, null: false
      t.datetime :submitted_at
      t.integer  :contest_type_id, default: 0, null: false
      t.boolean  :cancelled
      t.integer  :expected_payout
      t.timestamps
    end
  end
end
