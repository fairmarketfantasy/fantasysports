class RosterSerializer < ActiveModel::Serializer
  attributes :id, 
      :owner_id, 
      :market_id, 
      :state, 
      :contest_id, 
      :buy_in, 
      :remaining_salary, 
      :score, 
      :contest_rank, 
      :amount_paid, 
      :paid_at, 
      :cancelled_cause, 
      :cancelled_at, 
      :positions,
      :next_game_time,
      :live

  has_one :contest
  has_one :contest_type
  has_many :players

  def players
    @players ||= object.players_with_prices
  end

  def live
    object.live?
  end

end
