class GamesController < ApplicationController
  skip_before_filter :authenticate_user!, :only => [:for_market]

  def show
    game_stats_id = params[:id]
    seq_num = params[:sequence_number]
    @game_events = GameEvent.where(game_stats_id: game_stats_id)
    @game_events.after_seq_number(seq_num) if params[:sequence_number]
  end

  def for_market
    @market = Market.find(params[:id])
    render_api_response @market.games.order('game_time asc')
  end
end
