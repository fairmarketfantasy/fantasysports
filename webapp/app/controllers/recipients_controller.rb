class RecipientsController < ApplicationController

  def index
    recipient = current_user.recipient
    render_api_response recipient ? [recipient] : []
  end

  def create
    # begin
      recipient = Recipient.new(recipient_params.merge!(user: current_user))
      if recipient.save
        render_api_response recipient
      else
        render json: {errors: recipient.errors.full_messages}
      end
    # rescue => e
    #   msg = e.try(:message)
    #   render json: {error: msg || e}
    # end
  end

  private

    def recipient_params
      params.require(:recipient).permit(:name, :token)
    end

end