class Recipient < ActiveRecord::Base
  attr_accessor :token, :name

  belongs_to :user
  has_one    :customer_object, through: :user

  # validate  :user_must_be_confirmed
  validates :stripe_id, :user_id, presence: true

  before_validation :set_stripe_id, on: :create

  def reload
    @stripe_object = nil
    super
  end

  def user_must_be_confirmed
    errors.add(:user, "must be confirmed") unless user.confirmed?
  end

  def set_stripe_id
    unless token
      raise ArgumentError, "Must supply a bank account token from stripe.js"
    end
    resp = Stripe::Recipient.create({
                                      name: name,
                                      type:  "individual",
                                      email: user.email,
                                      bank_account: token
                                    })
    self.stripe_id = resp.id
  end

  def transfer(amount)
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