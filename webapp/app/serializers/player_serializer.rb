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
      :benched,
      :swapped_player_name

  def team
    Team.find_by_identifier(object[:team]).name
  end

  def ppg
    played_games_ids = StatEvent.where("player_stats_id='#{object.stats_id}' AND activity='points' AND quantity != 0" ).
                                 pluck('DISTINCT game_stats_id')
    events = StatEvent.where(player_stats_id: object[:stats_id],
                             game_stats_id: played_games_ids, activity: 'points')
    total_stats = StatEvent.collect_stats(events)[:points]
    return if total_stats.nil? || object[:total_games] == 0

    value = total_stats / played_games_ids.count
    value.round == 0 ? nil : value
  end

  def headshot_url
    object.headshot_url
  end

  def benched
    object.benched? ? true : false
  end
end
