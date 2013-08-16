class ContestsController < ApplicationController

  def join
    if request.get?
      #this is the inbound link from the invite code
      # params[:invitation_code]
      render json: {success: "success"}
    elsif request.post?
      #this actually joins them into the contest
    end
  end
end
