class ContestTypeSerializer < ActiveModel::Serializer
  attributes :id, :market_id, :name, :description, :max_entries, :buy_in, :rake, :payout_structure, :user_id, :private, :payout_description, :icon_url, :contest_class_desc

  CONTEST_CLASS_DESCRIPTIONS = {
    'h2h'  => "Challenge your friends to head to head games and channel some truly intimate aggression.",
    '194'  => "Top half nearly doubles their money. You're better than average, right? Go get 'em!",
    '970'  => "Show everyone what a true champion you are in this winner takes all league.",
    '100k' => "THE LOLLAPALOOZA. First prize is $50k, that's a lot of cheddar for a $10 entry!"
  }

  def contest_class_desc
    CONTEST_CLASS_DESCRIPTIONS[object.name]
  end

  def icon_url
    "/assets/icon-#{name}.png"
  end
end

