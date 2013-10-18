class CustomerObject < ActiveRecord::Base
  attr_accessor :token
  attr_protected

  belongs_to :user
  belongs_to :default_card
  has_many :credit_cards

  #override reload to nil out memoized stripe object
  def reload
    @strip_object = nil
    super
  end

  def delete_card(card_id)
    credit_card = CreditCard.find(card_id)
    paypal_credit_card = Paypal::SDK::REST::CreditCard.find(card_id)
    if paypal_credit_card.delete
      credit_card.deleted = true
      credit_card.save
    end
  end

  def charge(amount_in_cents)
    #strip api require charging at least 50 cents
    amount = amount_in_cents.to_i
    # begin
    resp = Stripe::Charge.create({
      amount:   amount,
      currency: "usd",
      customer: stripe_id,
    })
    increase_balance(resp.amount, 'deposit') # Don't change this without changing them elsewhere
    resp
    # rescue Stripe::CardError => e
    #   #card has been declined, handle this exception and log it somewhere
    #   raise e
    # end
  end

  def set_default_card(card_id)
    stripe_object.default_card = card_id
    stripe_object.save
  end

  def balance_in_dollars
    sprintf( '%.2f', (balance/100) )
  end

  # TODO: refactor this argument nonsense
  def increase_balance(amount, event, roster_id = nil, contest_id = nil, invitation_id = nil, referred_id = nil)
    ActiveRecord::Base.transaction do
      self.balance += amount
      TransactionRecord.create!(:user => self.user, :event => event, :amount => amount, :roster_id => roster_id, :contest_id => contest_id, :invitation_id => invitation_id, :referred_id => referred_id)
      self.save!
    end
  end

  def decrease_balance(amount, event, roster_id = nil, contest_id = nil, invitation_id = nil, referred_id = nil)
    ActiveRecord::Base.transaction do
      self.reload
      raise HttpException.new(409, "You're trying to transfer more than you have.") if self.balance - amount < 0 && self.user != SYSTEM_USER
      self.balance -= amount
      TransactionRecord.create!(:user => self.user, :event => event, :amount => -amount, :roster_id => roster_id, :contest_id => contest_id, :invitation_id => invitation_id, :referred_id => referred_id)
      self.save!
    end
  end

  def stripe_object
    #memoize stripe object
    @strip_object ||= Stripe::Customer.retrieve(stripe_id)
  end

end
