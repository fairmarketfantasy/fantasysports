class Recipient < ActiveRecord::Base
  attr_accessor :paypal_email_confirmation
  attr_accessible :paypal_email, :paypal_email_confirmation, :user

  belongs_to :user
  has_one    :customer_object, through: :user

  validate  :user_must_be_confirmed
  validates :paypal_email, :user_id, presence: true

  before_validation :confirm_email, on: :create

  def confirm_email
    errors.add(:email, "must match confirmation_email.") unless self.paypal_email == self.paypal_email_confirmation
  end

  def user_must_be_confirmed
    errors.add(:user, "must be confirmed.") unless user.confirmed?
  end

  def transfer(amount)
    # Build request object
    api = PayPal::SDK::AdaptivePayments.new
    pay = api.build_pay({
      :actionType => "PAY",
      :cancelUrl => "#{SITE}/samples/adaptive_payments/pay",
      :currencyCode => "USD",
      :feesPayer => "PRIMARYRECEIVER", #"SENDER",
      :ipnNotificationUrl => "#{ SITE }/samples/adaptive_payments/ipn_notify",
      :memo => "Withdrawal from FairMarketFantasy.com",
      :receiverList => {
        :receiver => [{
          :amount => amount.to_i/100.0, # TODO: validate this
          :email => self.paypal_email}],
      :returnUrl => "#{SITE }/samples/adaptive_payments/pay" }
    })
    
    # Make API call & get response
    response = api.pay(pay)
    debugger
    # Access response
    if response.success?
      response.payKey
      api.payment_url(response)  # Url to complete payment
    else
      response.error[0].message
    end
    amount = response.amount
    customer_object.decrease_balance(amount, "withdrawal")
  end

end
