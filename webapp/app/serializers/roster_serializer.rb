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
      :created_at, 
      :updated_at,
      :next_game_time,
      :live

  has_one :contest
  has_one :contest_type
  has_many :players


=begin
  There are essentially 4 active states for rosters and markets to be in:
  - in_progress, published
  - submitted, published
  - in_progress, opened
  - submitted, opened
  Only in the last state are price differentials important.  
  That also means that in cases 1-3 remaining salary is determined by the buy_price of the roster's players
=end
  def players
    @players ||= object.players_with_prices
  end

  def remaining_salary
    if (object.state == 'in_progress' || object.market.state == 'published')
      salary = object.contest_type.salary_cap
      players.each do |p|
        salary -= p.buy_price
      end
      salary
    else
      object.remaining_salary
    end
  end

  def live
    object.live?
  end

end
