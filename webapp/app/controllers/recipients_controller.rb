class RecipientsController < ApplicationController

  def index
    recipient = current_user.recipient
    render_api_response recipient ? [recipient] : []
  end

  def create
    begin
      recipient = Recipient.new(recipient_params.merge!(user: current_user))
      if recipient.save
        Eventing.report(current_user, 'addBankAccount')
        render_api_response recipient, status: :ok
      else
        render json: {error: recipient.errors.full_messages.first}, status: :unprocessable_entity
      end
    rescue => e
      msg = e.try(:message)
      render json: {error: Array(msg || e)}, status: :unprocessable_entity
    end
  end

  def destroy
    if current_user.recipient.delete
      render_api_response current_user.reload
    else
      render json: {error: ["There was a problem deleting that payout location, refresh and try again."]}
    end
  end

  private

    def recipient_params
      params.require(:recipient).permit(:paypal_email, :paypal_email_confirmation)
    end

end
