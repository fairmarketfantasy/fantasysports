class ContestsController < ApplicationController

  def for_market

  end

  def join
    if request.get?
      #this is the inbound link from the invite code
      # params[:invitation_code]
      render json: {success: "success"}
    elsif request.post?
      # Submit your roster to the contest
      roster = Roster.find(params[:roster_id])
      # TODO: validate roster
      Contest.submit_roster(roster)
      render json: roster
    end
  end

end
