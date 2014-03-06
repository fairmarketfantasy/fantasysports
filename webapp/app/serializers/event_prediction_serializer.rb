class EventPredictionSerializer < ActiveModel::Serializer
  attributes :event_type, :value, :diff
end
