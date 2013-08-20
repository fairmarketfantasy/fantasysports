class Roster < ActiveRecord::Base
  has_and_belongs_to_many :players, join_table: 'rosters_players', foreign_key: "contest_roster_id"
  belongs_to :contest
  belongs_to :owner, class_name: "User", foreign_key: :owner_id

  before_validation :set_remaining_salary

  validates :owner_id, :market_id, :contest_id, :buy_in, :remaining_salary, :contest_type, :state, presence: true

#state: "in_progress", "cancelled", "submitted"

  private

    def set_remaining_salary
      self.remaining_salary = 100
    end


end
