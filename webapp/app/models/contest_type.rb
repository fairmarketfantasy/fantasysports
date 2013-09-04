class ContestType < ActiveRecord::Base
  belongs_to :market
  belongs_to :user
  has_many :contests
  has_many :rosters
  # TODO: validate payout structure, ensure rake isn't settable
end
