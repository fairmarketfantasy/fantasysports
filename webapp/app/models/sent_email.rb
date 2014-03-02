class SentEmail < ActiveRecord::Base
  attr_protected
  validates :email_type, :inclusion => {in: %w(week_digest) }
  belongs_to :user
end
