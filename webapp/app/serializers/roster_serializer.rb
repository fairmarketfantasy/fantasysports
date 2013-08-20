class RosterSerializer < ActiveModel::Serializer
  attributes :id, :owner_id, :market_id, :state, :contest_type, :contest_id, :buy_in, :remaining_salary, :final_points, :finish_place, :amount_paid, :paid_at, :cancelled_cause, :cancelled_at, :created_at, :updated_at
end
