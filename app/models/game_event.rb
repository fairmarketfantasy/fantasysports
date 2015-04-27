class GameEvent < ActiveRecord::Base
  #because we have a column named "type" ActiveRecord gets all cute and tries to think
  #we are doing Single Table Inheritace, however we are not so lets just tell Active Record
  #to not use the type column and instead tell our inheritance column is something that doesn't exist
  self.inheritance_column = :_type_disabled

  validates :sequence_number, :type, :summary, :clock, :game_stats_id, presence: true

  scope :after_seq_number, ->(sq){ where("sequence_number > #{sq}") }
end