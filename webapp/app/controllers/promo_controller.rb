class PromoController < ApplicationController
  skip_before_filter :authenticate_user!, :only => [:create]
  # Drop a cookie on the client for future redemption (for signed out users)
  def create
    if current_user
      redirect_to :action => :redeem
      return
    end
    promo = Promo.where(['code = ? AND valid_until > ?', params[:code], Time.new]).first
    raise HttpException.new(404, "No such promotion") unless promo
    session[:promo_code] = promo.code
    render :nothing => true, :status => :ok
  end

  # Actually redeem a code
  def redeem
    promo = Promo.where(['code = ? AND valid_until > ? AND NOT only_new_users', params[:code], Time.new]).first
    raise HttpException.new(404, "No such promotion") unless promo
    promo.redeem!
    render :nothing => true, :status => :ok
  end
end
