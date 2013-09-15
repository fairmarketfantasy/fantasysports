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

  def players
    @players ||= object.players.with_sell_prices(object)
  end

  def remaining_salary
    salary = object.remaining_salary
    if object.state == 'in_progress'
      players.each do |p|
        salary -= p.purchase_price # TODO: Have Sean check this
      end
    end
    salary
  end

  def live
    object.live?
  end

end
