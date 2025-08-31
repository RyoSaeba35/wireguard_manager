class PagesController < ApplicationController
  skip_before_action :authenticate_user!
  
  def privacy
  end

  def terms
  end

  def logging
  end
end
