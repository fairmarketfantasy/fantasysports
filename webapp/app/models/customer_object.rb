class CustomerObject < ActiveRecord::Base
  attr_accessor :token

  belongs_to :user

  before_validation :set_stripe_id, on: :create


  def set_stripe_id
    unless token
      raise ArgumentError, "Must supply a card token from stripe.js"
    end
    resp = Stripe::Customer.create({
                                      description: "Customer for #{user.email}",
                                      card: token
                                    })
    self.stripe_id = resp.id
  end

  def add_a_card(token)
    stripe_obj = self.retrieve
    stripe_obj.cards.create({card: token})
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

  def balance_in_dollars
    sprintf( '%.2f', (balance/100) )
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
