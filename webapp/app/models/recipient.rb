class Recipient < ActiveRecord::Base

  belongs_to :user
  has_one    :customer_object, through: :user

  validate  :stripe_must_save
  validate  :user_must_be_confirmed
  validates :stripe_id, :user_id, :legal_name, :routing, :account_num, presence: true

  def user_must_be_confirmed
    errors.add(:user, "must be confirmed") unless user.confirmed?
  end

  #rescue stripe errors, save them to errors[:base],
  #if strip works, assign stripe_id
  def stripe_must_save
    begin
      resp = Stripe::Recipient.create({
                                      name: legal_name,
                                      type:  "individual",
                                      email: user.email,
                                      bank_account: { country:       'US',
                                                      routing_number: routing,
                                                      account_number: account_num
                                                    }
                                    })
      self.legal_name = resp.name
      self.stripe_id  = resp.id
    rescue => e
      errors[:base] << e.message
    end
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