class PagesController < ApplicationController
  skip_before_filter :authenticate_user!

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

end
