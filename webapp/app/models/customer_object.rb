class CustomerObject < ActiveRecord::Base
  attr_accessor :token
  attr_protected

  belongs_to :user
  belongs_to :default_card, :class_name => 'CreditCard'
  has_many :credit_cards

  #override reload to nil out memoized stripe object
  def reload
    @strip_object = nil
    super
  end

  def delete_card(card_id)
    card = credit_cards.find(card_id)
    if card.paypal_card_id
      paypal_credit_card = PayPal::SDK::REST::CreditCard.find(card.paypal_card_id)
      if paypal_credit_card.delete
        card.deleted = true
        card.save
      end
    else
      card.deleted = true
      card.save
    end
    if self.default_card.nil? || self.default_card.id == card.id
      set_default_card(self.credit_cards.active.first)
    end
  end

  def charge(amount_in_cents)
    #strip api require charging at least 50 cents
    raise "Customer has no default cards" unless default_card
    amount = amount_in_cents.to_i
    payment = PayPal::SDK::REST::Payment.new({
      intent: "sale",
      payer: {
        payment_method: "credit_card",
        funding_instruments: [
          {
            credit_card_token: {
              credit_card_id: self.default_card.paypal_card_id,
            }
          }
        ],
      },
      transactions: [
        {
          amount: {
            total: amount / 100,
            currency: "USD",
          },
          description: "Purchase on FairMarketFantasy.com"
        }
      ]
    })
    begin
      r = payment.create
    rescue => e
      Rails.logger.error(e)
      raise e
    end
    # TODO Save paypal transaction id # payment.id
    if r && payment.state == 'approved'
      increase_balance(payment.transactions.first.amount.total.to_i * 100, 'deposit', :transaction_data => {:paypal_transaction_id => payment.id}.to_json)
    end
    payment
  end

  def set_default_card(card_id)
    self.default_card = self.credit_cards.select{|c| c.id == card_id}.first
    self.save!
  end

  def balance_in_dollars
    sprintf( '%.2f', (balance/100) )
  end

  def increase_balance(amount, event, opts = {})
    ActiveRecord::Base.transaction do
      self.balance += amount
      TransactionRecord.create!({:user => self.user, :event => event, :amount => amount}.merge(opts))
      self.save!
    end
  end

  def decrease_balance(amount, event, opts = {})
    ActiveRecord::Base.transaction do
      self.reload
      raise HttpException.new(409, "You're trying to transfer more than you have.") if self.balance - amount < 0 && self.user != SYSTEM_USER
      self.balance -= amount
      TransactionRecord.create!({:user => self.user, :event => event, :amount => -amount}.merge(opts))
      self.save!
    end
  end

end
