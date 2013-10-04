class PushDevicesController < ApplicationController

  def create # or update
    data = JSON.parse(request.body.read)
    device = PushDevice.where(:device_id => data['device_id']).first
    if device
      device.update_attributes(:token => data['token'], :environment => data['environment'])
      if current_user != device.user
        device.user = current_user
        device.save!
      end
    else
      device = PushDevice.new(
          :device_id => data['device_id'],
          :device_type => data['device_type'],
          :token => data['token'],
          :environment => data['environment'])
      device.user = current_user
      device.save!
    end 
    render :status => :ok, :json => {}
  end

end
