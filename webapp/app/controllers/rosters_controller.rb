class RostersController < ApplicationController

  # Create a roster for a contest type
  def create
    market = Market.find(params[:market_id])
    roster = Roster.generate_contest_roster(current_user, market, params[:contest_type], params[:buy_in])
    render_api_response roster
  end

  def add_player
    roster = Roster.where(['owner_id = ? AND id = ?', current_user.id, params[:id]]).first
    player = Player.find(params[:player_id])
    order = roster.add_player(player)
    render_api_response order
  end

  def remove_player
    roster = Roster.where(['owner_id = ? AND id = ?', current_user.id, params[:id]]).first
    player = Player.find(params[:player_id])
    order = roster.remove_player(player)
    render_api_response order
  end

  def show
    roster = Roster.find(params[:id])
    render_api_response roster
  end
end

