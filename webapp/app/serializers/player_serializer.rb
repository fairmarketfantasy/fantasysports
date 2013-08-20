class PlayerSerializer < ActiveModel::Serializer
  attributes :id, :stats_id, :sport_id, :team, :name, :name_abbr, :birthdate, :height, :weight, :college, :position, :jersey_number, :status, :ppg

  def ppg
    1.0 * object[:total_points] / object[:total_games]
  end
end

