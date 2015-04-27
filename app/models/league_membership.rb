class LeagueMembership < ActiveRecord::Base
  attr_protected
  belongs_to :user
  belongs_to :league
end

