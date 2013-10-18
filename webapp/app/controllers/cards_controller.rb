class CardsController < ApplicationController

  def index
    if current_user.customer_object
      render_api_response current_user.customer_object
    else
      render_api_response []
    end
  end

  def create
    begin
      unless customer_object = current_user.customer_object
        customer_object = CustomerObject.create!(user: current_user)
      end
      CreditCard.generate(params[:type], params[:name], params[:cvc], params[:number], params[:exp_month], params[:exp_year])
      Eventing.report(current_user, 'addCreditCard')
      render_api_response customer_object.reload
    rescue => e
      raise e
      # msg = e.try(:message)
      # render json: {error: msg || e}, status: :unprocessable_entity
    end
  end

  def destroy
    current_user.customer_object.delete_card(params[:id])
    render_api_response current_user.customer_object.reload
  end
end
