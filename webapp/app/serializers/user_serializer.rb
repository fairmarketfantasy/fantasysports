class UserSerializer < ActiveModel::Serializer
  attributes :id, :name, :admin, :username, :email, :balance, :image_url, :win_percentile, :total_points, :joined_at, :token_balance, :provider,
    :amount, :bets, :winnings, :total_wins, :total_losses, :bonuses, :referral_code, :inviter_id, :currentSport # Leaderboard keys


  has_one :customer_object
  has_one :in_progress_roster
  has_many :leagues

  attribute :confirmed?, key: :confirmed

  def currentSport
    Sport.where('is_active').first.name
  end

  def balance
    object.customer_object.try(:balance) || 0
  end

  def joined_at
    object.created_at
  end

  def bonuses
    JSON.parse(object.bonuses || '{}')
  end

  def customer_object
    return unless scope
    scope.id == object.id ? object.customer_object : nil
  end

end
