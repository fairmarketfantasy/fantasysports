class RostersPlayer < ActiveRecord::Base
  belongs_to :roster
  belongs_to :player
end

