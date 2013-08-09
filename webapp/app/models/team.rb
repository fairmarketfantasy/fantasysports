class Team < ActiveRecord::Base
  has_many :players
  belongs_to :sport

  validates :sport_id, :abbrev, :name, :conference, :division, presence: true

  def games
    Game.where("home_team = #{self.id} OR away_team_id = #{self.id}")
  end

end
