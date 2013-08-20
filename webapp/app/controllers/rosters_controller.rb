class RostersController < ApplicationController

  # Create a roster for a contest type
  def create
    market = Market.find(params[:market_id])
    roster = Roster.generate_contest_roster(current_user, market, params[:contest_type], params[:buy_in])
    render_api_response roster
  end

end

