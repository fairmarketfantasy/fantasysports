class Member < ActiveRecord::Base
  belongs_to :competition
  belongs_to :memberable, polymorphic: true
  attr_protected
end
