class ContestsController < ApplicationController

  def for_market
    market = Market.find(params[:id])
    if ['opened', 'published'].include?(market.state)
      types = market.contest_types.public.order("name asc, buy_in asc")
      render_api_response types
    else
      render_api_response []
    end
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

  def create
    params[:user_id] = current_user.id
    contest = Contest.create_private_contest(params)
    roster = Roster.generate(current_user, contest.contest_type)
    roster.update_attribute(:contest_id, contest.id)
    send_invitations(contest, params[:message])
    render_api_response roster
  end

  def invite
    contest = Contest.find(params[:id])
    raise "You must post an invitation_code for private contests" if contest.private? && params[:invitation_code] != contest.invitation_code
    send_invitations(contest, params[:message])
    render :nothing => true, :status => 201
  end

  private

  def send_invitations(contest, message)
    params['invitees'].split(/[,\n]/).each do |email|
      Invitation.for_contest(current_user, email, contest, message)
    end
  end

end
