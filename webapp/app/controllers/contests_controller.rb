class ContestsController < ApplicationController

  def for_market
    market = Market.find(params[:id])
    types = market.contest_types.public.order("name asc, buy_in asc")
    render_api_response types
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
