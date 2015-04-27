class CreateLeagues < ActiveRecord::Migration
  def change
    create_table :league_contests do |t|
      t.integer :contest_id
      t.integer :league_id
      t.timestamps
    end

    create_table :league_membership do |t|
      t.integer :user_id
      t.integer :league_id
      t.timestamps
    end

    create_table :leagues do |t|
      t.string :name
      t.integer :buy_in
      t.integer :max_entries
      t.integer :takes_tokens
      t.integer :salary_cap
      t.timestamps
    end
  end
end
