class PlayersController < ApplicationController
  before_filter :authenticate_user!

  def index
    market = Market.find(params[:market_id])
    @players = Player.in_market(market)
    @players = @players.autocomplete(params[:autocomplete]) if params[:autocomplete]

    game = params[:game] ? Game.find(params[:game]) : nil
    scopes = { in_game: game, in_contest: params[:contest].presence }

    scopes.each do |s, val|
      if val
        @players.public_send(s, val)
      end
    end
    render_api_response @players
  end

end
