class SportSerializer < ActiveModel::Serializer
  attributes :id, :name, :is_active, :playoffs_on, :coming_soon
end

