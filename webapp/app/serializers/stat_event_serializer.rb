class StatEventSerializer < ActiveModel::Serializer
  attributes :id, :activity, :data, :point_value, :player_stats_id, :game_stats_id
end

