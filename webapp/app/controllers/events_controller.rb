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

    games = GamesMarket.where(:market_id => params[:market_id]).map(&:game_stats_id)
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
    games_ids = Game.where("game_time < now()").
                            where("(home_team = '#{player[:team] }' OR away_team = '#{player[:team] }')").
                            order("game_time DESC").map(&:id).uniq
    events = StatEvent.where(:player_stats_id => params[:player_ids], game_stats_id: games_ids)
    recent_events = events.where(game_stats_id: games_ids.first(5))

    recent_stats = StatEvent.collect_stats(recent_events)
    total_stats = StatEvent.collect_stats(events)

    data = []
    total_stats.each do |k, v|
      value = v.to_d / BigDecimal.new(player.total_games)
      value = value * 0.7 + recent_stats[k]/games_ids.first(5).count * 0.3 if recent_stats[k]

      data << { name: k, value: value.round(1) }
    end

    render json: { events: data }.to_json
  end
end
