class PagesController < ApplicationController
  skip_before_filter :authenticate_user!

  def index
  end

  def terms
  end

  def about
  end

end
