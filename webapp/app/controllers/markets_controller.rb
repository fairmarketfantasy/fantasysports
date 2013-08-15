class MarketsController < ApplicationController

  def index
    page = params[:page] || 1
    @markets = Market.page(page)
  end

  def contests
    if request.get?
      # Optionally Authenticated. Takes options in this format: {day: ‘2013-07-23’, after: ‘2013-07-22’, page: 1}. 
      # Default to today’s contests. List all open public contests, 
      # private contests (that are visible to me if logged in) and in-progress contests matching the criteria
    elsif request.post?
      authenticate_user!
      market   = Market.find(params[:id])
      user_cap = params[:user_cap]
      type     = params[:type]
      invitees = params[:emails]
      buy_in   = params[:buy_in]
      contest = market.contests.create!(owner:    current_user,
                                        user_cap: user_cap,
                                        buy_in:   buy_in,
                                        type:     type)
      invitees.each do |email|
        contest.invite(email)
      end
    end
  end

end
