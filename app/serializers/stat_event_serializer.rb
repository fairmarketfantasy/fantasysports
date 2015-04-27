class StatEventSerializer < ActiveModel::Serializer
  attributes :id, :activity, :data, :point_value, :player_stats_id, :game_stats_id

  def point_value
    object.point_value.round(2)
  end
end

