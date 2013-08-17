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
                                      card: card,
                                      token: token
                                    })
    super({stripe_id: resp.id, user_id: user.id})
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
      increase_balance(resp.amount)
      resp
    rescue Stripe::CardError => e
      #card has been declined, handle this exception and log it somewhere
      raise e
    end
  end

  def increase_balance(amount)
    ActiveRecord::Base.transaction do
      self.balance += amount
      self.save
    end
  end


  private

    def retrieve
      Stripe::Customer.retrieve(stripe_id)
    end

end
