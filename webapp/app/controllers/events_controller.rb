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
end
