class PushDevicesController < ApplicationController

  def create # or update
    device = PushDevice.where(:device_id => params['device_id']).first
    if device
      device.update_attributes(:token => params['token'], :environment => params['environment'])
      if current_user != device.user
        device.user = current_user
        device.save!
      end
    else
      device = PushDevice.new(
          :device_id => params['device_id'],
          :device_type => params['device_type'],
          :token => params['token'],
          :environment => params['environment'])
      device.user = current_user
      device.save!
    end 
    render :status => :ok, :json => {}
  end

end
