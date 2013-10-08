class ContestsController < ApplicationController
  skip_before_filter :authenticate_user!, :only => :join

  def for_market
    market = Market.find(params[:id])
    if ['opened', 'published'].include?(market.state)
      types = market.contest_types.public.order("name asc, takes_tokens = false desc, buy_in asc")
      render_api_response types
    else
      render_api_response []
    end
  end

  def join
    invitation = Invitation.where(:code => params[:referral_code]).first
    contest = Contest.where(:invitation_code => params[:contest_code]).first
    if current_user
      roster = Roster.generate(current_user, contest.contest_type)
      roster.update_attribute(:contest_id, contest.id)
      redirect_to "/#/market/#{roster.market_id}/roster/#{roster.id}"
    else
      flash[:success] = "You need to sign up or login to join this contest!"
      session[:referral_code] = invitation.code if invitation
      session[:contest_code] = contest.invitation_code
      redirect_to "/" #// Trigger sign up modal
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
