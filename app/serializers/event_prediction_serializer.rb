class EventPredictionSerializer < ActiveModel::Serializer
  attributes :id, :event_type, :value, :diff
end
