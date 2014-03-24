class IndividualPrediction < ActiveRecord::Base
  belongs_to :roster
  belongs_to :player
  belongs_to :user
  belongs_to :market
  has_many :event_predictions
  validates_presence_of :user_id, :player_id, :roster_id, :market_id, :pt
  attr_protected

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

    def create_individual_prediction(params, user)
      player = Player.where(stats_id: params[:player_id]).first
      event = params[:events].first
      pt = IndividualPrediction.get_pt_value(event[:value].to_d, event[:diff])
      prediction = user.individual_predictions.create(player_id: player.id,
                                                              roster_id: params[:roster_id],
                                                              market_id: params[:market_id],
                                                              pt: pt)
      TransactionRecord.create!(:user => user, :event => 'create_individual_prediction', :amount => pt * 100)
      Eventing.report(user, 'CreateIndividualPrediction', :amount => pt * 100)
      prediction
    end
  end

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
    TransactionRecord.create!(:user => current_user, :event => 'cancel_individual_prediction', :amount => self.pt * 100)
    Eventing.report(current_user, 'CancelIndividualPrediction', :amount => self.pt * 100)
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
