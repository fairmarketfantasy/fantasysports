class ContestSerializer < ActiveModel::Serializer
  attributes :id,
      :buy_in,
      :user_cap,
      :market_id,
      :invitation_code,
      :contest_type_id,
      :num_rosters,
      :paid_at,
      :private,
      :league_id
end
