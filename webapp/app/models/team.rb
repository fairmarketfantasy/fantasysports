class Team < ActiveRecord::Base
  has_many :players, :foreign_key => 'team'
  belongs_to :sport
  belongs_to :group
  has_many :members, as: :memberable
  has_many :competitions, through: :members

  attr_accessible *(%i(abbrev sport name market division state country stats_id conference))

  validates :sport_id, :abbrev, :name, presence: true # :conference, :division for NFL

  def games
    Game.where("home_team = '#{self.stats_id}' OR away_team = '#{self.stats_id}'")
  end

  def pt(opts = {})
    competition_type = opts[:type] || opts[:prediction_type]
    value = if opts[:game_stats_id].blank? && !competition_type.nil? && competition_type != 'daily_wins'
              PredictionPt.find_by_stats_id_and_competition_type(self.stats_id, competition_type).pt
            elsif Game.exists?(home_team: self.stats_id, stats_id: opts[:game_stats_id])
              Game.find_by_home_team_and_stats_id(self.stats_id, opts[:game_stats_id]).home_team_pt
            elsif Game.exists?(away_team: self.stats_id, stats_id: opts[:game_stats_id])
              Game.find_by_away_team_and_stats_id(self.stats_id, opts[:game_stats_id]).away_team_pt
            end

    user = opts[:user]
    value *= user.customer_object.contest_winnings_multiplier if user
    value = 15.01.to_d if value < 15.to_d
    value.round
  end

  def game_stats_id
  end

  def home_disable_pt
    Prediction.prediction_made?(object.home_team, 'daily_wins', object.stats_id) ||
      Prediction.prediction_made?(object.away_team, 'daily_wins', object.stats_id)
  end

  # Either an abbrev or a stats_id
  def self.find_by_identifier(identifier)
    (identifier.split('-').count > 2 ? Team.where(:stats_id => identifier) : Team.where(:abbrev => identifier)).first
  end

  def logo_url
    "https://fairmarketfantasy-prod.s3-us-west-2.amazonaws.com/" +
      "team-logos/#{self.sport.name.downcase}/#{self.name.gsub('`', '').gsub(' ','-').downcase}.png"
  end
end
