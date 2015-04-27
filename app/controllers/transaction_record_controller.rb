class TransactionRecordController < ApplicationController
  def index
    page = params[:page] || 1
    balance_event_types = %w(deposit withdrawal monthly_user_balance)
    render_api_response current_user.transaction_records.where(event: balance_event_types).order('id desc').page(page)
  end
end
