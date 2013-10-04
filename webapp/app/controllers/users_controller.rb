class UsersController < ApplicationController
  skip_before_filter :verify_authenticity_token, :only => [:create, :update]

  def index
    render_api_response current_user
  end

  def show
    user = User.find(params[:id])
    render_api_response user
  end

  def name_taken
    user = User.where(:username => params[:name]).first
    render_api_response({"result" => !user})
  end

  def set_username
    current_user.username = params[:name]
    current_user.save!
    render_api_response({"result" => !!current_user})
  end

  def add_money
    unless params[:amount]
      render json: {error: "Must supply an amount"}, status: :unprocessable_entity and return
    end
    current_user.customer_object.set_default_card(params[:card_id])
    if current_user.customer_object.charge(params[:amount])
      render_api_response current_user
    end
  end

  def token_plans
    render_api_response User::TOKEN_SKUS
  end

  def add_tokens
    current_user.transaction do
      if params[:receipt] # From iOS
        data = Venice::Receipt.verify(params[:receipt]).to_h
        raise HttpException.new(403, "That receipt has already been redeemed") if TransactionRecord.where(:ios_transaction_id => data[:transaction_id]).first
        current_user.token_balance += User::TOKEN_SKUS[data[:product_id]][:tokens]
        current_user.save!
        TransactionRecord.create!(:user => current_user, :event => 'token_buy_ios', :amount => User::TOKEN_SKUS[data[:product_id]], :ios_transaction_id => data[:transaction_id], :transaction_data => data.to_json)
      else
        current_user.customer_object.set_default_card(params[:card_id])
        sku = User::TOKEN_SKUS[params[:product_id]]
        if current_user.customer_object.charge(sku[:cost])
          current_user.token_balance += sku[:tokens]
          current_user.save!
          TransactionRecord.create!(:user => current_user, :event => 'token_buy', :amount => sku[:cost], :transaction_data => sku.to_json)
        end
      end
    end
    render_api_response current_user
  end

  def withdraw_money
    authenticate_user!
    unless params[:amount]
      render json: {error: "Must supply an amount"}, status: :unprocessable_entity and return
    end
    if current_user.recipient.transfer(params[:amount])
      render_api_response current_user.reload
    end
  end

end
