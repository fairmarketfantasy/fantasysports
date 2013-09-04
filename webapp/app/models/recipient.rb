class Recipient < ActiveRecord::Base

  belongs_to :user
  has_one    :customer_object, through: :user

  validate  :user_must_be_confirmed
  validates :stripe_id, :user_id, presence: true

  def user_must_be_confirmed
    errors.add(:user, "must be confirmed") unless user.confirmed?
  end

  def self.create(args={})
    token      = args[:token]
    user       = args[:user]
    legal_name = args[:legal_name]
    unless token
      raise ArgumentError, "Must supply a bank account token from stripe.js"
    end
    resp = Stripe::Recipient.create({
                                      name: legal_name,
                                      type:  "individual",
                                      email: user.email,
                                      bank_account: token
                                    })
    super({stripe_id: resp.id, user_id: user.id})
  end

  def transfer(amount)
    resp = Stripe::Transfer.create({
              amount:   amount,
              currency: 'usd',
              recipient: stripe_id,
              description: "Transfer for #{self.user.email}" #this shows up on the users bank statement after the SITE's url
            })
    amount = resp.summary.charge_gross
    customer_object.decrease_balance(amount, "transfer")
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
    @so ||= Stripe::Recipient.retrieve(stripe_id)
  end

  # # go fetch it again
  # def stripe_object!
  #   @so = Stripe::Recipient.retrieve(stripe_id)
  # end
end