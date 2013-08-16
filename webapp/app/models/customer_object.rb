class CustomerObject < ActiveRecord::Base

  belongs_to :user

  def charge(amount_in_cents)
    #strip api require charging at least 50 cents
    amount = amount_in_cents.to_i
    begin
      Stripe::Charge.create({
        amount:   amount,
        currency: "usd",
        customer: stripe_id,
      })
    rescue Stripe::CardError => e
      #card has been declined, handle this exception and log it somewhere
      raise e
    end
  end


  private

    def retrieve
      Stripe::Customer.retrieve(stripe_id)
    end

end
