class PlayerPosition < ActiveRecord::Base
  belongs_to :player

  attr_accessible :player_id, :position
end

