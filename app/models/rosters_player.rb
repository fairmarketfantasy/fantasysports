class RostersPlayer < ActiveRecord::Base
  attr_protected
  belongs_to :roster
  belongs_to :player

  validates_presence_of :position

  scope :with_market_players, ->(market) {
    select('rosters_players.*, market_players.locked'
        ).joins('JOIN market_players ON rosters_players.player_stats_id = market_players.player_stats_id'
        ).where(['market_players.market_id = ?', market.id])
  }

  def locked
    self[:locked]
  end
end
