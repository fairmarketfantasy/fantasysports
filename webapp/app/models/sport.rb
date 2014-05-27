class Sport < ActiveRecord::Base
  has_many :markets
  has_many :contests
  has_many :players
  has_many :teams
  has_many :games
  attr_accessible :name, :is_active, :playoffs_on

  scope :active, -> { where('is_active') }
end
