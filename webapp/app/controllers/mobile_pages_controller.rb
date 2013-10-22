class MobilePagesController < ApplicationController
  layout 'mobile_pages'
  skip_before_filter :authenticate_user!

  def forgot_password
  end

  def support
  end

  def terms
  end

  def rules
  end
end
