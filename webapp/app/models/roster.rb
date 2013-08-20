class Roster < ActiveRecord::Base
  has_and_belongs_to_many :players, join_table: 'rosters_players', foreign_key: "contest_roster_id"
  belongs_to :contest
  belongs_to :owner, class_name: "User", foreign_key: :owner_id

  validates :state, :inclusion => {in: %w( in_progress cancelled submitted ) }

  validates :owner_id, :market_id, :contest_id, :buy_in, :remaining_salary, :contest_type, :state, presence: true

#state: "in_progress", "cancelled", "submitted"

  def self.new_contest_roster(user, contest)
    Roster.create!(
      :owner => user,
      :market_id => contest.market_id,
      :contest_id => contest.id,
      :contest_type => contest.type,
      :buy_in => contest.buy_in,
      :remaining_salary => 100000,
      :state => 'in_progress',
    )
  end

end
