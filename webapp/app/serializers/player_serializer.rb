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

  # TODO: fix for NFL when no stats_id
  def team
    Team.find(object[:team]).name
  end

  def headshot_url
    object.headshot_url
  end

  def benched
    object.benched? ? true : false
  end

  def ppg
    return unless object.ppg

    object.ppg.round > 0 ? object.ppg : nil
  end
end
