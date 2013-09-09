class MarketsController < ApplicationController
  skip_before_filter :authenticate_user!

  def index
    page = params[:page] || 1
    @markets = Market.where(:state  => ['published', 'opened']).page(page).order('closed_at asc').limit(5)
    render_api_response @markets
  end

  def show
    @market = Market.find(params[:id])
    render_api_response @market
  end

  def contests
    if request.get?
      # Optionally Authenticated. Takes options in this format: {day: ‘2013-07-23’, after: ‘2013-07-22’, page: 1}. 
      # Default to today’s contests. List all open public contests, 
      # private contests (that are visible to me if logged in) and in-progress contests matching the criteria
    elsif request.post?
      authenticate_user!
      market       = Market.find(params[:id])
      user_cap     = params[:user_cap]
      contest_type = ContestType.find(params[:contest_type_id])
      invitees     = params[:emails]
      buy_in       = params[:buy_in]

      contest = Contest.create!(
        market: market,
        owner: current_user,
        user_cap: user_cap,
        buy_in: buy_in,
        contest_type: contest_type
        )
      contest.make_private
      invitees.each do |email|
        contest.invite(email)
      end
    end
  end

end
