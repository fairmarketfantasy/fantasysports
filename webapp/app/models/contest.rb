class Contest < ActiveRecord::Base
  belongs_to :sport
  has_many :games
  has_many :rosters

  # TODO: decide how to represent contest type, which could be multiple types. Bitmap? Another relation?
end
