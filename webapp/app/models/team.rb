class Team < ActiveRecord::Base
  self.primary_key = "abbrev"
  has_many :players, :foreign_key => 'team'
  belongs_to :sport

  attr_accessible *(%i(abbrev sport name market division state country stats_id conference))

  validates :sport_id, :abbrev, :name, presence: true # :conference, :division for NFL

  def games
    Game.where("home_team = #{self.id} OR away_team_id = #{self.id}")
  end

  # Either an abbrev or a stats_id
  def self.find_by_identifier(identifier)
    (identifier.split('-').count > 2 ? Team.where(:stats_id => identifier) : Team.where(:abbrev => identifier)).first
  end

end
