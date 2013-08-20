class UserSerializer < ActiveModel::Serializer
  attributes :id, :name, :admin, :email, :in_progress_roster
end
