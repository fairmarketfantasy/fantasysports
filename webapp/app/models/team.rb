class Team < ActiveRecord::Base
  self.primary_key = "abbrev"
  has_many :players, :foreign_key => 'team'
  belongs_to :sport

  validates :sport_id, :abbrev, :name, :conference, :division, presence: true

  def games
    Game.where("home_team = #{self.id} OR away_team_id = #{self.id}")
  end

end
