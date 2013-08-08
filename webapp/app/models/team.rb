class Team < ActiveRecord::Base
  has_many :players
  belongs_to :sport
  has_many :home_games, class_name: "Game", foreign_key: "home_team_id"
  has_many :away_games, class_name: "Game", foreign_key: "away_team_id"

  validates :sport_id, :abbrev, :name, :conference, :division, presence: true

  def games
    Game.where("home_team_id = #{self.id} OR away_team_id = #{self.id}")
  end

end
