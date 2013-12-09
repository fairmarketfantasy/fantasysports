class RosterSerializer < ActiveModel::Serializer
  attributes :id, 
      :owner_id, 
      :owner_name, # include whole object?
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
      :started_at,
      :market_id, # ios Dependency
      :next_game_time,
      :live,
      :bonus_points,
      :perfect_score,
      :view_code

  has_one  :league
  has_one  :contest
  has_one  :contest_type
  has_many :players
  has_one  :market

  def league
    object.contest && object.contest.league
  end

  def players
    @players ||= object.players_with_prices
  end

  def positions
    object.contest_type.positions
  end

  def live
    object.live?
  end

  def owner_name
    if object.is_generated?
      User::SYSTEM_USERNAMES[object.id % User::SYSTEM_USERNAMES.length]
    else
      object.owner.username
    end
  end

  def contest_rank_payout # api compatible attr name
    object.expected_payout
  end

end
