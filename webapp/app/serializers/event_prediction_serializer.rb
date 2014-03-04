class EventPredictionSerializer < ActiveModel::Serializer
  attributes :event_type, :value, :less_or_more
end
