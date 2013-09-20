class RosterSerializer < ActiveModel::Serializer
  attributes :id, 
      :owner_id, 
      :owner_name, # include whole object?
      :market_id, 
      :state, 
      :contest_id, 
      :buy_in, 
      :remaining_salary, 
      :score, 
      :contest_rank, 
      :contest_rank_payout, 
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

  def owner_name
    object.owner.name
  end

  def contest_rank_payout
    if object.contest_rank
      object.contest_type.payout_for_rank(object.contest_rank)
    else
      nil
    end
  end

end
