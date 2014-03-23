class IndividualPrediction < ActiveRecord::Base
  belongs_to :roster
  belongs_to :player
  belongs_to :user
  belongs_to :market
  has_many :event_predictions
  validates_presence_of :user_id, :player_id, :roster_id, :market_id, :pt
  attr_protected

  PT = BigDecimal.new(25)

  def submit!
    ActiveRecord::Base.transaction do
      customer_object = self.user.customer_object
      customer_object.monthly_contest_entries += Roster::FB_CHARGE
      customer_object.save!
    end
  end

  def cancel!
    ActiveRecord::Base.transaction do
      customer_object = self.user.customer_object
      customer_object.monthly_contest_entries -= Roster::FB_CHARGE
      customer_object.save!
    end
    self.update_attribute(:cancelled, true)
  end

  def won?
    game_ids = GamesMarket.where(:market_id => self.market.id).map(&:game_stats_id)
    events = StatEvent.where(:player_stats_id => self.player.stats_id, :game_stats_id => game_ids)
    game_stats = StatEvent.collect_stats(events)
    self.event_predictions.each do |prediction|
      game_result = game_stats[prediction.event_type] || 0
      self.update_attribute(:game_result, game_result.to_i)
      if prediction.diff == 'more'
        return false if prediction.value > game_result
      elsif prediction.diff == 'less'
        return false if prediction.value < game_result
      else
        raise "Unexpected diff value!"
      end
    end

    true
  end
end
