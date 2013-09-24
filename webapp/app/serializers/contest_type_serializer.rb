class ContestTypeSerializer < ActiveModel::Serializer
  attributes :id, :market_id, :name, :description, :max_entries, :buy_in, :rake, :payout_structure, :user_id, :private, :payout_description, :icon_url

  def icon_url
    "/assets/icon-#{name}.png"
  end
end

