class IndividualPredictionsController < ApplicationController
  def create
    player = Player.where(stats_id: params[:player_id]).first
    prediction = current_user.individual_predictions.create(player_id: player.id,
                                                            roster_id: params[:roster_id],
                                                            market_id: params[:market_id])
    params[:events].each do |k, v|
      event_prediction = prediction.event_predictions.create(event_type: k,
                                                             value: v[:point],
                                                             less_or_more: v[:diff])
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
