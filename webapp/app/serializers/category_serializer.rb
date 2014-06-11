class CategorySerializer < ActiveModel::Serializer
  attributes :id, :name, :note, :is_new, :title
  has_many :sports
end
