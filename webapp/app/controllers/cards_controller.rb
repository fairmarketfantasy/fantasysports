class CardsController < ApplicationController

  def index
    if current_user.customer_object
      render_api_response current_user.customer_object
    else
      render_api_response []
    end
  end

  def create
    # begin
      if co = current_user.customer_object
        co.add_a_card(params[:token])
      else
        co = CustomerObject.create(user: current_user, token: params[:token])
      end
      render_api_response co
    # rescue => e
    #   msg = e.try(:message)
    #   render json: {error: msg || e}
    # end
  end
end