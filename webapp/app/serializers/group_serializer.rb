class GroupSerializer < ActiveModel::Serializer
  attributes :name

  has_many :teams

  def teams
    object.teams.map { |t| TeamSerializer.new(t, {type: 'win_groups', user: options[:user]}) }
  end
end
