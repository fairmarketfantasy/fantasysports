class PlayersController < ApplicationController
  before_filter :authenticate_user!

  def index
    game = params[:game] ? Game.find(params[:game]) : nil
    scopes = { in_game: game, in_contest: params[:contest].presence }
    @players = Player.autocomplete(params[:autocomplete])
    scopes.each do |s, val|
      if val
        @players.public_send(s, val)
      end
    end
  end

end
