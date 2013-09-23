class StatEvent < ActiveRecord::Base
  attr_protected
  #because we have a column named "type" ActiveRecord gets all cute and tries to think
  #we are doing Single Table Inheritace, however we are not so lets just tell Active Record
  #to not use the type column and instead tell our inheritance column is something that doesn't exist
  self.inheritance_column = :_type_disabled

  #I don't think Active Record is going to be saving these records, but what the hell,
  #doesn't hurt to have AR validations that match the database-level constraints
  validates :game_stats_id, :player_stats_id, :point_value, presence: true
end
