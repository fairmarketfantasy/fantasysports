class RecipientsController < ApplicationController

  def index
    recipients = current_user.recipients
    render_api_response recipients
  end

  def create
    recipient = Recipient.create(recipient_params.merge!(user: current_user))
    if recipient.valid?
      render_api_response recipient
    else
      render json: {errors: recipient.errors.full_messages}
    end
  end

  private

    def recipient_params
      params.require(:recipient).permit(:legal_name, :routing, :account_num)
    end

end