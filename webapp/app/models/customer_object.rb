class CustomerObject < ActiveRecord::Base
  attr_accessor :token
  attr_protected

  belongs_to :user
  belongs_to :default_card, :class_name => 'CreditCard'
  has_many :credit_cards

  def self.monthly_accounting!
    condition = 'is_active AND has_agreed_terms AND last_activated_at < ?'
    CustomerObject.where([condition, Time.new.beginning_of_month]).each do |co|
      co.do_monthly_accounting!
    end
  end

  def do_monthly_accounting!
    return if !self.last_activated_at && trial_active?

    user_earnings = taxed_net_monthly_winnings
    tax_earnings = self.net_monthly_winnings - user_earnings
    condition = (user_earnings + tax_earnings) - (self.monthly_winnings - self.monthly_contest_entries * 1000) == 0
    raise "Monthly accounting doesn't add up" unless condition

    self.class.transaction do
      #decrease_monthly_winnings(user_earnings, :event => 'monthly_user_balance')
      #decrease_monthly_winnings(deficit_entries * 1000, :event => 'monthly_user_entries') if deficit_entries > 0
      #decrease_monthly_winnings(tax_earnings, :event => 'monthly_taxes') if tax_earnings > 0
      if self.net_monthly_winnings > 0
        increase_account_balance(user_earnings, :event => 'monthly_user_balance')
        self.update_attributes(:monthly_contest_entries => 0)
      elsif self.net_monthly_winnings < -5000
        self.update_attributes(:monthly_contest_entries => 5)
      else
        self.update_attributes(:monthly_contest_entries => self.net_monthly_winnings.abs/1000)
      end

      self.update_attributes(:monthly_winnings => 0, :monthly_entries_counter => 0)
      puts "--Accounting #{self.user.id}"
      if self.balance > 1000
        do_monthly_activation!
      end
    end
  end

  def do_monthly_activation!
    return if (self.is_active && self.last_activated_at && self.last_activated_at > Time.new.beginning_of_month) ||
      trial_active?
    self.is_active = false
    if self.balance >= 1000
      self.balance -= 1000
      self.is_active = true
      self.last_activated_at = Time.new
      puts "--Activated #{self.user.id}"
    end
    self.save!
  end

  def taxed_net_monthly_winnings
    return net_monthly_winnings if net_monthly_winnings <= 10000

    sum = net_monthly_winnings
    [10000, 30000, 50000].each do |tier|
      sum -= 0.25.to_d * (net_monthly_winnings - tier) if net_monthly_winnings >= tier
    end

    sum
  end

  def net_monthly_winnings
    self.monthly_winnings - self.monthly_contest_entries * 1000
  end

  def entries_in_the_hole
    self.monthly_contest_entries + self.contest_entries_deficit * 1.5
  end

  def contest_winnings_multiplier
    # Exclude the current contest when counting bonus
    1 + ([net_monthly_winnings, 0].min * -0.0005)/100.to_d
  end

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
          description: "Purchase on PredictThat.com"
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

  def increase_monthly_contest_entries!(amount, opts = {})
    ActiveRecord::Base.transaction do
      TransactionRecord.create!(opts.merge({:user => self.user, :amount => amount, :is_monthly_entry => true}))
      self.monthly_contest_entries += amount
      self.monthly_entries_counter += 1
      self.save!
    end
  end

  def decrease_monthly_contest_entries!(amount, opts = {})
    ActiveRecord::Base.transaction do
      TransactionRecord.create!(opts.merge({:user => self.user, :amount => -amount, :is_monthly_entry => true}))
      self.monthly_contest_entries -= amount
      self.monthly_entries_counter -= 1
      self.save!
    end
  end

  def increase_monthly_winnings(amount, opts = {})
    ActiveRecord::Base.transaction do
      self.monthly_winnings += amount
      TransactionRecord.create!(opts.merge({:user => self.user, :event => opts[:event], :amount => amount, :is_monthly_winnings => true}))
      self.save!
    end
  end

  def decrease_monthly_winnings(amount, opts = {})
    ActiveRecord::Base.transaction do
      self.monthly_winnings -= amount
      TransactionRecord.create!(opts.merge({:user => self.user, :amount => -amount, :is_monthly_winnings => true}))
      self.save!
    end
  end

  def increase_account_balance(amount, opts = {})
    ActiveRecord::Base.transaction do
      self.balance += amount
      TransactionRecord.create!({:user => self.user, :event => opts[:event], :amount => amount}.merge(opts))
      self.save!
    end
  end

  def decrease_account_balance(amount, opts = {})
    ActiveRecord::Base.transaction do
      self.reload
      raise HttpException.new(409, "You're trying to transfer more than you have.") if self.balance - amount < 0 && self.user.id != SYSTEM_USER.id
      self.balance -= amount
      TransactionRecord.create!({:user => self.user, :event => opts[:event], :amount => -amount}.merge(opts))
      self.save!
    end
  end

  def deactivate_account
    self.update_attributes(is_active: false, trial_started_at: Date.today - 16)
    card_ids = self.credit_cards.pluck(:id)
    card_ids.each { |id| self.delete_card(id) }
    self.reload
  end

  def trial_active?
    self.trial_started_at && self.trial_started_at + 15 >= Date.today
  end
end
