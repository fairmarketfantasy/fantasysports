class RosterSerializer < ActiveModel::Serializer
  attributes :id,
      :owner_id,
      :owner_name, # include whole object?
      :state,
      :contest_id,
      :buy_in,
      :remaining_salary, # abridged
      :score,
      :contest_rank,
      :contest_rank_payout,
      :amount_paid,
      :paid_at,
      :cancelled_cause,
      :cancelled_at,
      :positions, # abridged
      :started_at,
      :market_id, # ios Dependency
      :next_game_time,
      :live, # abridged
      :bonus_points,
      :perfect_score,
      :remove_benched,
      :view_code,
      :abridged

  has_one  :league # abridged
  has_one  :contest # abridged
  has_one  :contest_type # abridged
  has_many :players # abridged
  has_one  :market # abridged

  def abridged
    scope.abridged? ? true : false
  end

  def remaining_salary
    scope.abridged? ? nil : object.remaining_salary
  end

  def contest_type
    scope.abridged? ? nil : object.contest_type
  end

  def market
    scope.abridged? ? nil : object.market
  end

  def next_game_time
    scope.abridged? ? nil : object.next_game_time
  end

  def contest
    scope.abridged? ? nil : object.contest
  end

  def league
    scope.abridged? ? nil : object.contest && object.contest.league
  end

  def players
    scope.abridged? ? [] : @players ||= object.players_with_prices
  end

  def positions
    return if scope.abridged?

    Positions.for_sport_id(object.market.sport_id)
  end

  def live
    scope.abridged? ? nil : object.live?
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

  # This doesn't actually work to filter out associations. Doh.
  def attributes
    hash = super
    if scope.abridged?
      #[:players, :positions, :live, :next_game_time, :contest, :contest_type, :market].each{|k| hash.delete(k) }
    end
    hash
  end

end
