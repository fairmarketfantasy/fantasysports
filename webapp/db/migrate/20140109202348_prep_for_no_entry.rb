class PrepForNoEntry < ActiveRecord::Migration
  def change
    add_column :customer_objects, :has_agreed_terms, :boolean, :default => false
    add_column :customer_objects, :is_active, :boolean, :default => false
    add_column :customer_objects, :monthly_winnings, :integer, :default => 0
    add_column :customer_objects, :monthly_contest_entries, :integer, :default => 0
    add_column :customer_objects, :contest_entries_deficit, :decimal, :default => 0
    add_column :transaction_records, :is_monthly_winnings, :boolean
    add_column :transaction_records, :is_monthly_entry, :boolean

  end
end
