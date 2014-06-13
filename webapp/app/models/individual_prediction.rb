class IndividualPrediction < Prediction

  self.table_name = 'individual_predictions'

  belongs_to :market
  belongs_to :player
  has_many :event_predictions
  attr_protected
  validates_presence_of :market_id

  PT = BigDecimal.new(25)

  class << self

    def get_pt_value(value, diff)
      if value < 0.5
        if diff == "less"
          chance =(1/(1 - value)-1)
        elsif diff == "more"
          chance =(1/value-1)
        else
          raise "Unknow diff value"
        end
        pt = (chance * 0.7 + 1) * Roster::FB_CHARGE * 10
        pt.round(2).to_d
      else
        PT
      end
    end

    def create_prediction(params, user)
      player = Player.where(stats_id: params[:player_id]).first
      event = params[:events].first
      pt = IndividualPrediction.get_pt_value(event[:value].to_d, event[:diff])
      prediction = user.individual_predictions.create!(player_id: player.id,
                                                       market_id: params[:market_id],
                                                       pt: pt)
      TransactionRecord.create!(:user => user, :event => 'create_individual_prediction',
                                :amount => pt * 100)
      Eventing.report(user, 'CreateIndividualPrediction', :amount => pt * 100)
      customer_object = user.customer_object
      customer_object.monthly_entries_counter += 1
      customer_object.save!
      prediction
    end
  end

  def charge_owner
    ActiveRecord::Base.transaction do
      customer_object = self.user.customer_object
      customer_object.monthly_contest_entries += Roster::FB_CHARGE
      customer_object.save!
    end
  end

  def cancel!
    user = self.user
    ActiveRecord::Base.transaction do
      customer_object = user.customer_object
      customer_object.monthly_contest_entries -= Roster::FB_CHARGE
      customer_object.monthly_entries_counter -= 1
      customer_object.save!
    end
    TransactionRecord.create!(:user => user, :event => 'cancel_individual_prediction', :amount => Roster::FB_CHARGE * 1000)
    Eventing.report(user, 'CancelIndividualPrediction', :amount => Roster::FB_CHARGE * 1000)
    self.update_attribute(:state, 'canceled')
  end

  def won?
    game_ids = GamesMarket.where(:market_id => self.market.id).map(&:game_stats_id)
    events = StatEvent.where(:player_stats_id => self.player.stats_id, :game_stats_id => game_ids)
    sport_name = self.market.sport.name
    position = sport_name == 'MLB' ? self.player.positions.first.try(:position) : nil
    game_stats = SportStrategy.for(sport_name).collect_stats(events, position)
    self.event_predictions.each do |prediction|
      game_result = game_stats[prediction.event_type.to_sym] || 0
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

  def payout
    customer_object = user.customer_object
    amount_value = self.pt * 100 * customer_object.contest_winnings_multiplier
    ActiveRecord::Base.transaction do
      customer_object.monthly_winnings += amount_value
      customer_object.save!
    end
    TransactionRecord.create!(:user => user, :event => 'individual_prediction_win', :amount => amount_value)
    Eventing.report(user, 'IndividualPredictionWin', :amount => amount_value)
    user.update_attribute(:total_wins, user.total_wins.to_i + 1)
    self.update_attribute(:award, self.pt * customer_object.contest_winnings_multiplier)
  end
end
