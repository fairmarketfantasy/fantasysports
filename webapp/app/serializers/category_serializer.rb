class CategorySerializer < ActiveModel::Serializer
  attributes :id, :name, :note
  has_many :sports
end
