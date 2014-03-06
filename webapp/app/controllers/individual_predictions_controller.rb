class IndividualPredictionsController < ApplicationController
  def create
    player = Player.where(stats_id: params[:player_id]).first
    prediction = current_user.individual_predictions.create(player_id: player.id,
                                                            roster_id: params[:roster_id],
                                                            market_id: params[:market_id],
                                                            pt: IndividualPrediction::PT)
    params[:events].each do |event|
      event_prediction = prediction.event_predictions.create(event_type: event[:name],
                                                             value: event[:value],
                                                             diff: event[:diff])
      if event_prediction.errors.any?
        return render :text => k + ' ' + event_prediction.errors.full_messages.join(', '),
          status: :unprocessable_entity
      end
    end

    render :text => 'Individual prediction submitted successfully!', :status => :ok
  end

  def show
  end

  def mine
    render_api_response current_user.individual_predictions
  end

  def update
  end
end
