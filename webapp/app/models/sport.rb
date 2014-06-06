class Sport < ActiveRecord::Base

  belongs_to :category

  has_many :markets
  has_many :contests
  has_many :players
  has_many :teams
  has_many :games
  has_many :groups
  attr_accessible :name, :coming_soon, :category_id, :is_active, :playoffs_on

  scope :active, -> { where('is_active') }
end
