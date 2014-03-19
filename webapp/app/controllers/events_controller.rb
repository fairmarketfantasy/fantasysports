class EventsController < ApplicationController
=begin
  These functions take a hash of game_stats_ids to sequence numbers.
  This allows clients to only ask for new data, rather than getting
  a dump of all game data every time it polls.
  TODO: consider pagination
=end
  def for_game
    game = Game.find(params[:id])
    render_api_response eventsFromIndexes([game], params[:indexes])
  end

  # Takes an array of player_stat_ids and a market
  def for_players
    return render_average(params) if params[:average]

    games = GamesMarket.where(:market_id => params[:market_id]).pluck('DISTINCT game_stats_id')
    events = StatEvent.where(:player_stats_id => params[:player_ids], :game_stats_id => games)
    render_api_response events
  end

  def for_roster
    roster = Roster.find(params[:id])
    games = roster.games
    render_api_response eventsFromIndexes(games, params[:indexes])
  end

  def for_my_rosters
    rosters = current_user.rosters.active.select{|r| r.live?}
    games = rosters.map(&:games).flatten
    render_api_response eventsFromIndexes(games, indexes)
  end

  private

  def eventsFromIndexes(games, indexes)
    conditions = ""
    args = []
    if indexes
      conditions = indexes.map do |k,v|
        args << k << v
        "(stats_id = ? AND sequence_number > ?)"
      end.join(' ')
    end
    GameEvent.where(:game_stats_id => games.map(&:stats_id)).where([conditions] + args)
  end

  def render_average(params)
    player = Player.where(:stats_id => params[:player_ids]).first
    played_games_ids = StatEvent.where("player_stats_id='#{params[:player_ids]}' AND activity='points' AND quantity != 0" ).
                                 pluck('DISTINCT game_stats_id')
    games = Game.where(stats_id: played_games_ids)
    events = StatEvent.where(player_stats_id: params[:player_ids],
                             game_stats_id: played_games_ids)
    recent_games = games.order("game_time DESC").first(5)
    recent_ids = recent_games.map(&:stats_id)
    recent_events = events.where(game_stats_id: recent_ids)

    recent_stats = StatEvent.collect_stats(recent_events)
    total_stats = StatEvent.collect_stats(events)
    bid_ids = current_bid_ids(params[:market_id], player.id)

    data = []
    total_stats.each do |k, v|
      value = v.to_d / BigDecimal.new(played_games_ids.count)
      value = value * 0.7 + (recent_stats[k] || 0.to_d)/recent_ids.count * 0.3
      bid_less = false
      bid_more = false
      if bid_ids.any?
        bid_less = true if EventPrediction.where(event_type: k.to_s, diff: 'less', individual_prediction_id: bid_ids).first
        bid_more = true if EventPrediction.where(event_type: k.to_s, diff: 'more', individual_prediction_id: bid_ids).first
      end

      data << { name: k, value: value.round(1), bid_less: bid_less, bid_more: bid_more }
    end

    render json: { events: data }.to_json
  end

  def current_bid_ids(market_id, player_id)
    return unless current_user

    IndividualPrediction.where(user_id: current_user,
                               market_id: market_id,
                               player_id: player_id).pluck(:id)
  end
end
