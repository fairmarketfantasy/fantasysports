class RecipientsController < ApplicationController

  def index
    recipient = current_user.recipient
    render_api_response recipient || []
  end

  def create
    # begin
      recipient = Recipient.create(recipient_params.merge!(user: current_user))
      if recipient.new_record?
        render json: {errors: [recipient.errors[:base].first] || recipient.errors.full_messages}
      else
        render_api_response [recipient]
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