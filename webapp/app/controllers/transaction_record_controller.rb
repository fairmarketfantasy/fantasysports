class TransactionRecordController < ApplicationController
  def index
    page = params[:page] || 1
    balance_event_types = %w(payout joined_grant token_buy token_buy_ios revert_transaction
                             free_referral_payout paid_referral_payout referred_join_payout deposit withdrawal
                             manual_payout promo monthly_user_balance monthly_taxes monthly_user_entries)
    render_api_response current_user.transaction_records.where(event: balance_event_types).order('id desc').page(page)
  end
end
