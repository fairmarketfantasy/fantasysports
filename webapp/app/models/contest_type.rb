class ContestType < ActiveRecord::Base
  belongs_to :user
  has_many :contests
  # TODO: validate payout structure, ensure rake isn't settable
end
