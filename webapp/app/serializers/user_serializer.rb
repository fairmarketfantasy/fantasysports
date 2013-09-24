class UserSerializer < ActiveModel::Serializer
  attributes :id, :name, :admin, :email, :balance, :image_url, :win_percentile, :total_points, :total_wins, :joined_at
  has_one :in_progress_roster

  attribute :confirmed?, key: :confirmed

  def balance
    object.customer_object.try(:balance) || 0
  end

  def joined_at
    object.created_at
  end
end
