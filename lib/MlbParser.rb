class MlbParser

  def parse_season_stat_events(game_id, data)
    stat_event = @game.stat_events.where(:player_stats_id => batter['batter_id'].to_s,
                                         :activity => POINTS_MAPPER[batter['action']][0]).first
    stat_event ||= @game.stat_events.new
  end
end
