class AddTrialStartedAtToCustomerObject < ActiveRecord::Migration
  def change
    add_column :customer_objects, :trial_started_at, :date
  end
end
