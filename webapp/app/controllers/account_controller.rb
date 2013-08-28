class AccountController < ApplicationController

  def recipients
    recipients = current_user.recipients
    render_api_response recipients
  end

end