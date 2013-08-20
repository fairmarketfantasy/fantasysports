class WebhooksController < ApplicationController

  def new
    event_json = JSON.parse(request.body.read)
    case event_json.class
    #freeze customer object when a dispute is created
    when Stripe::Dispute
      dispute         = event_json
      charge_id       = dispute.charge
      charge          = Stripe::Charge.retrieve(id)
      customer        = charge.card.customer
      customer_object = Customer.find_by(stripe_id: customer)
      customer_object.update_attributes(locked: true, locked_reason: dispute.reason)
    end
  end


end