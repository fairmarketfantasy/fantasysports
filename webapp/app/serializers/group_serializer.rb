class GroupSerializer < ActiveModel::Serializer
  attributes :name

  has_many :teams

  def teams
    object.teams.map { |t| TeamSerializer.new(t, options) }
  end
end
