class RecipientsController < ApplicationController

  def index
    recipients = current_user.recipients
    render_api_response recipients
  end

  def create
    recipient = Recipient.create(recipient_params.merge!(user: current_user))
    if recipient.new_record?
      render json: {errors: recipient.errors[:base].first || recipient.errors.full_messages}
    else
      render_api_response recipient
    end
  end

  private

    def recipient_params
      params.require(:recipient).permit(:legal_name, :routing, :account_num)
    end

end