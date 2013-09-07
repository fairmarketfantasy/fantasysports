class UserSerializer < ActiveModel::Serializer
  attributes :id, :name, :admin, :email, :balance, :image_url
  has_one :in_progress_roster

  def balance
    object.customer_object.try(:balance_in_dollars)
  end
end
