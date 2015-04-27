class AddNumGeneratedToContests < ActiveRecord::Migration
  def change
    add_column :contests, :num_generated, :integer, :default => 0
  end
end
