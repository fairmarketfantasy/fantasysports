class PagesController < ApplicationController
  skip_before_filter :authenticate_user!, :except => [:support]

  def index
    unless current_user
      render layout: 'landing'
    end
  end

  def landing
    render layout: "landing"
  end

  def terms
    render layout: nil
  end

  def about
  end

  def guide
  	render layout: "guide"
  end

  def support
    SupportMailer.support_mail(params[:title], params[:email], params[:message]).deliver!
    render :nothing => true, :status => :ok
  end
end
