class RostersPlayer < ActiveRecord::Base
  attr_protected
  belongs_to :roster
  belongs_to :player
end

