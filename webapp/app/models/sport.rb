class Sport < ActiveRecord::Base
  has_many :markets
  has_many :contests
  has_many :players
  has_many :teams
end
