class Recipient < ActiveRecord::Base
  attr_accessor :paypal_email_confirmation, :name
  attr_protected

  belongs_to :user
  has_one    :customer_object, through: :user

  validate  :user_must_be_confirmed
  validates :paypal_email, :user_id, presence: true

  before_validation :confirm_email, on: :create

  def reload
    @stripe_object = nil
    super
  end

  def confirm_email
    errors.add(:email, "must match confirmation_email.") unless self.paypal_email == self.paypal_email_confirmation
  end

  def user_must_be_confirmed
    errors.add(:user, "must be confirmed.") unless user.confirmed?
  end

  def transfer(amount)
    @api = PayPal::SDK::AdaptivePayments.new

    # Build request object
    @pay = @api.build_pay({
      :actionType => "PAY",
      #:cancelUrl => "http://localhost:3000/samples/adaptive_payments/pay",
      :currencyCode => "USD",
      :feesPayer => "PRIMARYRECEIVER", #"SENDER",
      :ipnNotificationUrl => "#{ SITE }/samples/adaptive_payments/ipn_notify",
      :memo => "Withdrawal from FairMarketFantasy.com",
      :receiverList => {
        :receiver => [{
          :amount => 1.0,
          :email => "platfo_1255612361_per@gmail.com" }] },
      :returnUrl => "#{ SITE }/samples/adaptive_payments/pay" })
    
    # Make API call & get response
    @response = @api.pay(@pay)
    
    # Access response
    if @response.success?
      @response.payKey
      @api.payment_url(@response)  # Url to complete payment
    else
      @response.error[0].message
    end
    resp = Stripe::Transfer.create({
              amount:   amount,
              currency: 'usd',
              recipient: stripe_id,
              description: "Transfer for #{self.user.email}" #this shows up on the users bank statement after the SITE's url
            })
    amount = resp.amount
    customer_object.decrease_balance(amount, "withdrawal")
  end

  #attributes from STRIPE API
  def bank_name
    stripe_object.active_account.bank_name
  end

  def legal_name
    stripe_object.name
  end

  def last4
    stripe_object.active_account.last4
  end

  def stripe_object
    #memoize the retrieving of the stripe object...
    @stripe_object ||= Stripe::Recipient.retrieve(stripe_id)
  end

  # # go fetch it again
  # def stripe_object!
  #   @so = Stripe::Recipient.retrieve(stripe_id)
  # end
end
