class ContestType < ActiveRecord::Base
  attr_protected
  belongs_to :market
  belongs_to :user
  has_many :contests
  has_many :rosters

  scope :public, -> { where('private = false OR private IS NULL') }
  # TODO: validate payout structure, ensure rake isn't settable
end
