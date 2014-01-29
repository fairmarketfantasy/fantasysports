class PlayerPosition < ActiveRecord::Base
  belongs_to :player
  attr_protected
end

