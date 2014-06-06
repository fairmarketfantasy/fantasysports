class PlayerPrediction < Prediction

  self.table_name = 'player_predictions'

  # if you are correct you win 45 Fanbucks
  PT = BigDecimal.new(45)

  class << self

    def create_prediction(params, user)
      player = Player.where(id: params[:player_id]).first
      user.player_predictions.create!(player_id: player.id, user: user, pt: player.pt)
      TransactionRecord.create!(:user => user, :event => 'create_player_prediction',
                                :amount => Roster::FB_CHARGE * 1000)
      Eventing.report(user, 'CreatePlayerPrediction', :amount => Roster::FB_CHARGE * 1000)
      customer_object = user.customer_object
      customer_object.monthly_entries_counter += 1
      customer_object.save!
    end
  end

  def won?
    # something like
    players_query = Player.where(:team => 'MVP', :sport_id => self.player.sport_id)
    players_query.first.player_id == self.player_id and players_query.count == 1
  end
end