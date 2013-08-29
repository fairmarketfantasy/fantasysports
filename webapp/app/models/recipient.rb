class Recipient < ActiveRecord::Base

  belongs_to :user
  has_one    :customer_object, through: :user

  validates :stripe_id, :user_id, :legal_name, :routing, :account_num, presence: true
  validate  :user_must_be_confirmed

  def user_must_be_confirmed
    errors.add(:user, "must be confirmed") unless user.confirmed?
  end

  def self.create(args={})
    user  = args[:user]
    name        = args[:legal_name] || user.name
    account_num = args[:account_num]
    routing     = args[:routing]
    # begin
      resp = Stripe::Recipient.create({
                                      name:  name,
                                      type:  "individual",
                                      email: user.email,
                                      bank_account: { country:       'US',
                                                      routing_number: routing,
                                                      account_number: account_num
                                                    }
                                    })
    # rescue => e
      #TODO handle bad request, i.e. routing number must be 9 chars, etc...
    # end
    super({ user_id:     user.id,
            stripe_id:   resp.id,
            legal_name:  resp.name,
            account_num: account_num,
            routing:     routing
            })
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
end