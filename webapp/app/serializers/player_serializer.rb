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
      :swapped_player_name,
      :pt,
      :logo_url,
      :disable_pt,
      :remove_pt

  def disable_pt
    Prediction.prediction_made?(stats_id, 'mvp', '', options[:user])
  end

  def remove_pt
    object.pt.try(:round) <= 15.0
  end

  # TODO: fix for NFL when no stats_id
  def team
    Team.where(:stats_id => object[:team]).first.try(:name)
  end

  def headshot_url
    object.headshot_url
  end

  def logo_url
    object.headshot_url
  end

  def stats_id
    object.stats_id || object.id.to_s
  end

  def benched
    object.benched? ? true : false
  end

  def pt
    object.adjusted_pt(options).try(:round)
  end

  def ppg
    return unless object.ppg

    object.ppg.round > 0 ? object.ppg : nil
  end
end
