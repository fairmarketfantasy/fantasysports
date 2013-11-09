class CardsController < ApplicationController

  def index
    if current_user.customer_object
      render_api_response current_user.customer_object
    else
      render_api_response []
    end
  end

  def add_url
    url = NetworkMerchants.add_customer_form(params[:callback])
    render_api_response({url: url})
  end

  def token_redirect_url
    #headers['Access-Control-Allow-Origin'] = SITE
    #headers['Access-Control-Request-Method'] = '*'
    card = NetworkMerchants.add_customer_finalize(current_user.customer_object, params['token-id'])
    callback = 'jsonp_' + params[:callback]
    render_api_response current_user.customer_object, :callback => callback
  end

  def charge_url
    card = (params[:card_id] && current_user.customer_object.credit_cards.find(params[:card_id]) ) || current_user.customer_object.default_card
    url = NetworkMerchants.charge_form(:callback => params[:callback], :amount => sprintf("%0.02f", params[:amount].to_f), :card => card)
    render_api_response({url: url})
  end

  def charge_redirect_url
    NetworkMerchants.charge_finalize(current_user.customer_object, params['token-id'])
    callback = 'jsonp_' + params[:callback]
    render_api_response current_user, :callback => callback
  end

  def create
    begin
      unless customer_object = current_user.customer_object
        customer_object = CustomerObject.create!(user: current_user)
      end
      CreditCard.generate(customer_object, params[:type], params[:name], params[:number], params[:cvc], params[:exp_month], params[:exp_year])
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
