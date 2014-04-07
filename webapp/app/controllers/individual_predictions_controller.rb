class IndividualPredictionsController < ApplicationController
  def create
    raise HttpException.new(402, "Agree to terms!") unless current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, "Unpaid subscription!") if !current_user.active_account? && !current_user.customer_object.trial_active?

    prediction = IndividualPrediction.create_individual_prediction(params, current_user)
    params[:events].each do |event|
      if prediction.event_predictions.where(event_type: event[:name], value: event[:value], diff: event[:diff]).first
        return render 'You already have such prediction!', status: :unprocessable_entity
      end
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
    prediction = IndividualPrediction.find(params[:id])

    render_api_response individual_prediction
  end

  def mine
    sport = Sport.where(:name => params[:sport]).first if params[:sport]
    sport ||= Sport.where('is_active').first
    predictions = current_user.individual_predictions

    page = params[:page] || 1
    if params[:historical]
      predictions = predictions.where(state: ['finished', 'canceled'])
    elsif params[:all]
      predictions = predictions
    else
      predictions = predictions.where(state: 'submitted')
    end

    render_api_response predictions.page(page)
  end
end
