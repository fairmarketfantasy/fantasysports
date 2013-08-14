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
      # Authenticated.  This challenges a specific person to a head to head. 
      # Takes a list of email addresses, a market, a type (“194” is the only type supported for now) and a max number of users.
      # Create a new, private contest in the market.  Create a roster for this user and this contest.  Charge them for entry.  
      # Send their friend(s) an email challenging them to join the league and create their own fantasy sports roster.
    end
  end

end
