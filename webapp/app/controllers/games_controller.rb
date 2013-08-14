class GamesController < ApplicationController
  before_filter :authenticate_user!

  def show
    game_stats_id = params[:id]
    seq_num = params[:sequence_number]
    @game_events = GameEvent.where(game_stats_id: game_stats_id)
    @game_events.after_seq_number(seq_num) if params[:sequence_number]
  end

end
