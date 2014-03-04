class IndividualPredictionsController < ApplicationController
  def create
    prediction = current_user.individual_predictions.create(player_id: params[:player_id],
                                                            roster_id: params[:roster_id])
    params.each do |k, v|
      event_types = ['assists', 'turnovers', 'rebounds', 'points', '3pt made',
                     'steals', 'blocks']
      if event_types.include?(k)
        event_prediction = prediction.event_predictions.create(event_type: k,
                                                               value: v[1],
                                                               less_or_more: v[0])
        if event_prediction.errors.any?
          render :text => errors.map(&:full_messages).join(', '), status: :unprocessable_entity and return
        end
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
