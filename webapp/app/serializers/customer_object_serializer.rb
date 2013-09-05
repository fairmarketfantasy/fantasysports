class CustomerObjectSerializer < ActiveModel::Serializer
  attributes :id, :balance, :locked, :locked_reason, :cards

  def cards
    stripe_obj = object.retrieve
    stripe_obj.cards.data.map do |card|
      { id:          card.id,
        name:        card.name,
        last4:       card.last4,
        type:        card.type,
        exp_month:   card.exp_month,
        exp_year:    card.exp_year,
        address_zip: card.address_zip }
    end
  end
end
