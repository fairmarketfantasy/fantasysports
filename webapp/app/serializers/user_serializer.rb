class UserSerializer < ActiveModel::Serializer
  attributes :id, :name, :admin, :email
  has_one :in_progress_roster
end
