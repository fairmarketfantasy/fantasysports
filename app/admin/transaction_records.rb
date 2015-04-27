ActiveAdmin.register TransactionRecord do
  actions :all, except: [:destroy]
  filter :user_id
  filter :event

  index do
=begin
 id                      | integer                     | not null default nextval('transaction_records_id_seq'::regclass)
 event                   | character varying(255)      | not null
 user_id                 | integer                     |
 roster_id               | integer                     |
 amount                  | integer                     |
 contest_id              | integer                     |
 is_tokens               | boolean                     | default false
 ios_transaction_id      | character varying(255)      |
 transaction_data        | text                        |
 invitation_id           | integer                     |
 referred_id             | integer                     |
 created_at              | timestamp without time zone |
 updated_at              | timestamp without time zone |
 reverted_transaction_id | integer                     |

=end
    column :id
    column :event
    column :user_id
    column :amount
    column :is_tokens
    column :roster_id
    column :transaction_data
    column :reverted_transaction
    column :invitation_id
    column :created_at
    default_actions
  end
end

