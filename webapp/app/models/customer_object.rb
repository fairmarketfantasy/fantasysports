class CustomerObject < ActiveRecord::Base

  belongs_to :user

  #takes {token: "string", user: user, card: {}}
  #must supply either a token from stripe.js or a card object
  # card object:
  #      {
  #         number:    "4242424242424242",
  #         exp_month: 10,
  #         exp_year:  2015,
  #         cvc:       123,
  #         name:      "Jack Johnson"
  #       }
  def self.create(args={})
    token = args[:token]
    card  = args[:card]
    user  = args[:user]
    unless token || card
      raise ArgumentError, "Must supply either a token from stripe.js or a card"
    end
    resp = Stripe::Customer.create({
                                      description: "Customer for #{user.email}",
                                      card: card || token
                                    })
    super({stripe_id: resp.id, user_id: user.id})
  end

  ##Talk to Stripe API
  def self.find_by_charge_id(id)
    charge          = Stripe::Charge.retrieve(id)
    customer        = charge.card.customer
    self.find_by(stripe_id: customer)
  end

  def charge(amount_in_cents)
    #strip api require charging at least 50 cents
    amount = amount_in_cents.to_i
    begin
      resp = Stripe::Charge.create({
        amount:   amount,
        currency: "usd",
        customer: stripe_id,
      })
      increase_balance(resp.amount, 'deposit')
      resp
    rescue Stripe::CardError => e
      #card has been declined, handle this exception and log it somewhere
      raise e
    end
  end

  def increase_balance(amount, event)
    ActiveRecord::Base.transaction do
      self.balance += amount
      TransactionRecord.create!(:user => self.user, :event => event, :amount => amount)
      self.save
    end
  end

  def decrease_balance(amount, event, roster_id)
    ActiveRecord::Base.transaction do
      self.reload
      raise HttpException.new(402, "Insufficient funds") if self.balance - amount < 0
      self.balance -= amount
      TransactionRecord.create!(:user => self.user, :event => event, :amount => -amount, :roster_id => roster_id)
      self.save
    end
  end

  def retrieve
    Stripe::Customer.retrieve(stripe_id)
  end

end
