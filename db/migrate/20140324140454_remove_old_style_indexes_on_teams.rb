class RemoveOldStyleIndexesOnTeams < ActiveRecord::Migration
  def self.up

    change_table :teams do |t|
      t.change :division, :string, null: true
      t.change :conference, :string, null: true
    end

    remove_index :teams, column: [:abbrev, :sport_id]

  end

  # use old-style up & down methods, otherwise the migration is irreversible
  def self.down

    change_table :teams do |t|
      t.change :division, :string, null: false
      t.change :conference, :string, null: false
    end

    add_index :teams, [:abbrev, :sport_id], :unique => true

  end
end
