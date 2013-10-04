class PushDevice < ActiveRecord::Base
  attr_accessible :token, :environment, :device_type, :device_id
  belongs_to :user
end 

