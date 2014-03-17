class PlayerSerializer < ActiveModel::Serializer
  attributes :id,
      :stats_id,
      :team,
      :sport_id,
      :name,
      :name_abbr,
      :birthdate,
      :height,
      :weight,
      :college,
      :position,
      :jersey_number,
      :status,
      :ppg,
      :purchase_price,
      :buy_price,
      :sell_price,
      :score,
      :locked,
      :headshot_url,
      :is_eliminated,
      :benched_games,
      :next_game_at,
      :benched

  def team
    Team.find_by_identifier(object[:team]).name
  end

  def ppg
    games_ids = Game.where("game_time < now()").
                     where("(home_team = '#{object[:team] }' OR away_team = '#{object[:team] }')").
                     order("game_time DESC").map(&:id).uniq
    events = StatEvent.where(player_stats_id: object[:stats_id],
                             game_stats_id: games_ids, activity: 'points')
    total_stats = StatEvent.collect_stats(events)[:points]
    return 0 if object[:total_games].nil? || object[:total_games] == 0

    total_stats || 0 / object[:total_games]
  end

  def headshot_url
    object.headshot_url
  end

  def benched
    object.benched? ? true : false
  end
end
