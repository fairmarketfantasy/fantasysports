class GamesController < ApplicationController
  before_filter :authenticate_user!

  def show
    game_stats_id = params[:id]
    @game_events = GameEvent.where(game_stats_id: game_stats_id)
  end

end
