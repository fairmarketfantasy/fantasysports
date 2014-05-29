class Category < ActiveRecord::Base
  has_many :sports

  validates :name, presence: true

  attr_accessible :id, :name, :note
  default_scope order('id ASC')
end
