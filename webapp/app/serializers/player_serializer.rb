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
      :next_game_at

  def team
    Team.find_by_identifier(object[:team]).name
  end

  def ppg
    1.0 * object[:total_points] / object[:total_games]
  end

  def headshot_url
    object.headshot_url
  end
end

