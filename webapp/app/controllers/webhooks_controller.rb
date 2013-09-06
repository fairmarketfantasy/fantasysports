class WebhooksController < ApplicationController
  skip_before_filter :authenticate_user!

  def new
    event_json = JSON.parse(request.body.read).with_indifferent_access
    case event_json[:type]
    #freeze customer object when a dispute is created
    when "charge.dispute.created"
      dispute         = event_json
      charge_id       = dispute[:charge]
      customer_object = CustomerObject.find_by_charge_id(charge_id)
      customer_object.update_attributes(locked: true, locked_reason: dispute[:reason])
      render json: {message: "got the webhook"}, status: :ok
    end
  end

  private


end