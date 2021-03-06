class StatEvent < ActiveRecord::Base
  attr_protected

  #I don't think Active Record is going to be saving these records, but what the hell,
  #doesn't hurt to have AR validations that match the database-level constraints
  validates :game_stats_id, :player_stats_id, :point_value, presence: true

  belongs_to :game, :foreign_key => 'game_stats_id', :inverse_of => :stat_events
  # This bullshit doesn't work because the FK doesn't point at the id column
  belongs_to :player, :foreign_key => 'player_stats_id', :inverse_of => :stat_events, :primary_key => :stats_id
  #def player
  #  Player.where(['stats_id = ?', self.player_stats_id])
  #end
end
