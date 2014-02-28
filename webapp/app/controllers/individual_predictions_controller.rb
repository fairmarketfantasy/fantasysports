class IndividualPredictionsController < ApplicationController
  def create
    errors = ['bound', 'point', 'assist'].each_with_object([]) do |event, errors|
      choice, value = params[event]
      prediction = IndividualPrediction.new(roster_player_id: params[:roster_player_id],
                                            event_type: event,
                                            value: value,
                                            less_or_more: choice)
      prediction.save || errors << event.capitalize + ' ' +
                           prediction.errors.full_messages.join(', ').downcase
    end

    if errors.any?
      render :text => errors.join(', '), status: :unprocessable_entity
    else
      render :text => 'Individual prediction submitted successfully!', :status => :ok
    end
  end

  def show
  end

  def update
  end
end
