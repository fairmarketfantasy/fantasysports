class PlayersController < ApplicationController
  before_filter :authenticate_user!

  def index
    roster = Roster.find(params[:roster_id])
    @players = roster.purchasable_players.normal_positions
    @players = @players.autocomplete(params[:autocomplete]) if params[:autocomplete]

    game = params[:game] ? Game.find(params[:game]) : nil
    scopes = { in_game: game, in_contest: params[:contest].presence, in_position: params[:position].presence, on_team: params[:team].presence}


    scopes.each do |s, val|
      if val
        @players = @players.public_send(s, val)
      end
    end
    render_api_response @players.order('id asc')#.limit(50).page(params[:page] || 1)
  end

  def for_roster
    roster = Roster.find(params[:id])
    players = roster.players.with_purchase_price.with_scores
    render_api_response players
  end

end
