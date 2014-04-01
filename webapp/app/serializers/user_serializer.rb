class UserSerializer < ActiveModel::Serializer
  attributes :id, :name, :admin, :username, :email, :balance, :image_url, :win_percentile, :total_points, :joined_at, :token_balance, :provider,
    :amount, :bets, :winnings, :total_wins, :total_losses, :bonuses, :referral_code, :inviter_id, :currentSport, :in_progress_roster_id, # Leaderboard keys
    :abridged

  has_one :customer_object
  has_one :in_progress_roster
  has_many :leagues

  attribute :confirmed?, key: :confirmed

  def abridged
    scope.abridged? ? true : false
  end

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
    return if scope.nil? || scope.abridged?
    scope.id == object.id ? object.customer_object : nil
  end

  def in_progress_roster
    return if scope.nil? || scope.abridged?
    object.in_progress_roster
  end

  def in_progress_roster_id
    object.in_progress_roster.try(:id)
  end

  def admin
    scope.abridged? ? nil : object.admin
  end

  def total_losses
    object.total_loses
  end

  def win_percentile
    object.total_wins.to_d * 100 / (object.total_loses + object.total_wins)
  end

end
