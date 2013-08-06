class CreateMarkets < ActiveRecord::Migration
  def change
    create_table :markets do |t|
      t.string :name
      t.integer :shadow_bets, :null => false
      t.integer :shadow_bet_rate, :null => false
      t.timestamp :opened_at, :null => false
      t.timestamp :closed_at
      t.timestamps
    end

    create_table :market_players do |t|
      t.integer :market_id, :null => false
      t.integer :player_id, :null => false
      t.decimal :initial_price, :null => false
    end
    add_index :market_players, [:player_id, :market_id], :unique => true

    add_column :contests, :market_id, :integer, :null => false
    add_index :contests, :market_id

    rename_table :contest_rosters, :rosters


    add_column :rosters, :market_id, :integer, :null => false # I assume denormalizing here makes sean's life easier
    add_column :rosters, :contest_id, :integer, :null => false
    add_column :rosters, :buy_in, :integer, :null => false
    # add_column :rosters, :salary_cap, :decimal, :null => false # This is the same everywhere for now. We may want it eventually.
    add_column :rosters, :remaining_salary, :decimal, :null => false
    add_column :rosters, :is_valid, :boolean, :null => false, :default => false
    add_column :rosters, :final_points, :integer
    add_column :rosters, :finish_place, :integer
    add_column :rosters, :amount_paid, :decimal
    add_column :rosters, :paid_at, :timestamp
    add_column :rosters, :cancelled, :boolean, :null => false, :default => false
    add_column :rosters, :cancelled_cause, :string
    add_column :rosters, :cancelled_at, :timestamp
    add_index :rosters, :market_id
    add_index :rosters, :contest_id
    add_index :rosters, :cancelled

    rename_table :contest_rosters_players, :rosters_players

    create_table :market_orders do |t|
      t.integer :market_id, :null => false
      t.integer :contest_id, :null => false
      t.integer :roster_id, :null => false
      t.string :action, :null => false # create, open, close, buy, sell
      t.integer :player_id, :null => false
      t.decimal :price, :null => false
      t.boolean :rejected
      t.string :rejected_reason
      t.timestamps
    end

  end
end
