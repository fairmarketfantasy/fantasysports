class ContestTypeSerializer < ActiveModel::Serializer
  attributes :id, :market_id, :name, :description, :max_entries, :buy_in, :rake, :payout_structure, :user_id, :private
end

