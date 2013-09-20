class RecipientsController < ApplicationController

  def index
    recipient = current_user.recipient
    render_api_response recipient ? [recipient] : []
  end

  def create
    begin
      recipient = Recipient.new(recipient_params.merge!(user: current_user))
      if recipient.save
        render_api_response recipient
      else
        render json: {errors: recipient.errors.full_messages}
      end
    rescue => e
      msg = e.try(:message)
      render json: {errors: Array(msg || e)}
    end
  end

  def destroy
    stripe_object = current_user.recipient.stripe_object
    if stripe_object.delete
      current_user.recipient.delete
      render_api_response current_user.reload
    else
      render json: {errors: ["There was a problem deleting that bank account, refresh and try again."]}
    end
  end

  private

    def recipient_params
      params.require(:recipient).permit(:name, :token)
    end

end