class CustomerObjectSerializer < ActiveModel::Serializer
  attributes :id, :balance, :locked, :locked_reason, :cards

  def cards
    object.credit_cards.select{|c| !c.deleted }.map do |card|
      { id:          card.id,
        first_name:  card.first_name,
        last_name:   card.last_name,
        type:        card.card_type,
        exp_month:   card.expires.month,
        exp_year:    card.expires.year,
        #address_zip: card.address_zip,
        obscured_number: card.obscured_number,
        default:     card.id == object.default_card_id
      }
    end
  end

end
