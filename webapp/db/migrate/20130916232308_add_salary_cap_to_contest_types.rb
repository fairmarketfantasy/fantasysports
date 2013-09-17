class AddSalaryCapToContestTypes < ActiveRecord::Migration
  def change
    add_column :contest_types, :salary_cap, :integer
  end
end
