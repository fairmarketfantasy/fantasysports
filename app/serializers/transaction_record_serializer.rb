=begin
id                 | integer                     | not null default nextval('transaction_records_id_seq'::regclass)
 event              | character varying(255)      | not null
 user_id            | integer                     |
 roster_id          | integer                     |
 amount             | integer                     |
 contest_id         | integer                     |
 is_tokens          | boolean                     | default false
 ios_transaction_id | character varying(255)      |
 transaction_data   | text                        |
 invitation_id      | integer                     |
 referred_id        | integer                     |
 created_at         | timestamp without time zone |
 updated_at         | timestamp without time zone |
=end
class TransactionRecordSerializer < ActiveModel::Serializer
  attributes :id, :event, :user_id, :is_tokens, :amount, :created_at, :updated_at
  has_one :roster
  has_one :contest
  has_one :referred_user

  def referred_user
    object.referred
  end

  def event
    object.event.gsub('_', ' ').gsub(/^[a-z]|\s+[a-z]/) { |a| a.upcase }
  end

  def amount
    value = object.amount
    (value == Roster::FB_CHARGE ? value * 1000 : value).round(2)
  end
end
