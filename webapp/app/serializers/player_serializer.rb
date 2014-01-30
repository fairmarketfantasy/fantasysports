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
      # TODO Make these multiple
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
    object[:team]
  end

  def ppg
    1.0 * object[:total_points] / object[:total_games]
  end

  def headshot_url
    object.headshot_url
  end
end

