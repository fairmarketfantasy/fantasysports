class EmailUnsubscribe < ActiveRecord::Base
  attr_protected

  def self.has_unsubscribed?(email, type)
    EmailUnsubscribe.where(:email => email, :email_type => ['all', type]).first
  end
end
