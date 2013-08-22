class PlayerSerializer < ActiveModel::Serializer
  attributes :id, :stats_id, :team, :sport_id, :name, :name_abbr, :birthdate, :height, :weight, :college, :position, :jersey_number, :status, :ppg, :purchase_price

  def team
    object[:team]
  end

  def ppg
    1.0 * object[:total_points] / object[:total_games]
  end
end

