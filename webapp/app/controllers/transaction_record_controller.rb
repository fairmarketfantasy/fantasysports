class TransactionRecordController < ApplicationController
  def index
    page = params[:page] || 1
    render_api_response current_user.transaction_records.order('id desc').page(page)
  end
end
