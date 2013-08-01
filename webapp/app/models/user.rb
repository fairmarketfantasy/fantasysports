class User < ActiveRecord::Base
  has_many :contest_rosters
end
