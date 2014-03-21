class CustomerObjectSerializer < ActiveModel::Serializer
  attributes :id, :balance, :net_monthly_winnings, :monthly_contest_entries, :contest_entries_deficit,
      :locked, :locked_reason, :cards, :is_active, :has_agreed_terms, :contest_winnings_multiplier,
      :trial_started_at

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

  def monthly_contest_entries
    object.monthly_contest_entries / Roster::FB_CHARGE
  end

  def contest_winnings_multiplier
    object.contest_winnings_multiplier
  end

end
