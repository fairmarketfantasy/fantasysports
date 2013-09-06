class RosterSerializer < ActiveModel::Serializer
  attributes :id, 
      :owner_id, 
      :market_id, 
      :state, 
      :contest_id, 
      :buy_in, 
      :remaining_salary, 
      :final_points, 
      :finish_place, 
      :amount_paid, 
      :paid_at, 
      :cancelled_cause, 
      :cancelled_at, 
      :positions,
      :created_at, 
      :updated_at

  has_one :contest
  has_one :contest_type
  has_many :players

  def players
    object.sellable_players
  end

end
