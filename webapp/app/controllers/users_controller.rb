class UsersController < ApplicationController
  skip_before_filter :verify_authenticity_token, :only => [:create, :update, :unsubscribe]
  skip_before_filter :authenticate_user!, :only => [:reset_password]

  def index
    render_api_response current_user
  end

  def show
    user = User.find(params[:id])
    render_api_response user
  end

  def unsubscribe
    user = User.where(:email => params[:email]).first
    raise HttpException.new(403, "You must be logged in as the unsubscribing user to do that") if user && user != current_user
    @type = params[:type] || 'all'
    EmailUnsubscribe.create(:email => params[:email], :email_type => @type)
    render :layout => false
  end

  def name_taken
    user = User.where(:username => params[:name]).first || params[:name]
    render_api_response({"result" => !user})
  end

  def set_username
    current_user.username = params[:name]
    current_user.save!
    render_api_response({"result" => !!current_user})
  end

  def reset_password
    if user = User.find_by(email: params[:email])
      user.send_reset_password_instructions
      render_api_response({message: "Password reset instructions send to #{user.email}"})
    else
      render :json => {error: "No user with that email #{params[:email]}" }, status: :unprocessable_entity
    end
  end

  def paypal_return
    payer_id = params[:PayerID]
    payment = PayPal::SDK::REST::Payment.find(cookies[:pending_payment])
    payment.execute(payer_id: payer_id)
    @amount_in_cents = payment.transactions.first.amount.total.to_i * 100
    @type = params[:type]
    if @type == 'money'
      current_user.customer_object.increase_account_balance(@amount_in_cents, :event => 'deposit', :transaction_data => {:paypal_transaction_id => payment.id}.to_json)
      current_user.customer_object.do_monthly_activation!
      Invitation.redeem_paid(current_user)
      Eventing.report(current_user, 'addFunds', :amount => @amount_in_cents)
    elsif @type == 'token'
      @tokens, opts = User::TOKEN_SKUS.find{|tokens, opts| opts[:cost] == @amount_in_cents}
      current_user.token_balance += @tokens.to_i
      current_user.save!
      TransactionRecord.create!(:user => current_user, :event => 'token_buy', :amount => @amount_in_cents, :transaction_data => opts.to_json)
      Eventing.report(current_user, 'buyTokens', :amount => @amount_in_cents)
    end
    cookies.delete :pending_payment
    render '/users/paypal_return', layout: false
  end

  def paypal_waiting
    render '/users/paypal_waiting', layout: false
  end

  def paypal_cancel
    render '/users/paypal_cancel', layout: false
  end

  def generate_paypal_payment(type, amount)
    payment = PayPal::SDK::REST::Payment.new({  :intent => "sale",
                                                :payer => {
                                                  :payment_method => "paypal" },
                                                :redirect_urls => {
                                                  :return_url => "#{SITE}/users/paypal_return/#{type}",
                                                  :cancel_url => "#{SITE}/users/paypal_cancel" },
                                                :transactions => [ {
                                                :amount => {
                                                  :total => sprintf("%0.02f", amount.to_f / 100),
                                                  :currency => "USD" },
                                                :description => (type == 'money' ? "Deposit funds" : "Purchase FanFrees") + " for your Fair Market Fantasy account!" } ] } )
    if payment.create
      #second link is the approval url, obviously...
      approval_url = payment.links.second.href
      cookies[:pending_payment] = payment.id
      render json: {approval_url:  approval_url}
    else
      render json: {error: payment.error.message}, status: :unprocessable_entity
    end

  end

  def add_money
    unless params[:amount]
      render json: {error: "Must supply an amount"}, status: :unprocessable_entity and return
    end
    generate_paypal_payment('money', params[:amount].to_i * 100)
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

  def agree_to_terms
    current_user.customer_object.update_attribute :has_agreed_terms, true
    render_api_response current_user
  end

end
