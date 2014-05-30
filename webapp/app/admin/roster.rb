ActiveAdmin.register Roster do
  actions :all, except: [:destroy]
  filter :submitted_at
  filter :market_id
  filter :contest_id
  filter :owner_id
  filter :state

  index do
    column :id
=begin
 id               | integer                     | not null default nextval('rosters_id_seq'::regclass)
 owner_id         | integer                     | not null
 created_at       | timestamp without time zone |
 updated_at       | timestamp without time zone |
 market_id        | integer                     | not null
 contest_id       | integer                     |
 buy_in           | integer                     | not null
 remaining_salary | numeric                     | not null
 score            | integer                     |
 contest_rank     | integer                     |
 amount_paid      | numeric                     |
 paid_at          | timestamp without time zone |
 cancelled_cause  | character varying(255)      |
 cancelled_at     | timestamp without time zone |
 state            | character varying(255)      | not null
 positions        | character varying(255)      |
 submitted_at     | timestamp without time zone |
 contest_type_id  | integer                     | not null default 0
 cancelled        | boolean                     | default false
 wins             | integer                     |
 losses           | integer                     |
 takes_tokens     | boolean                     |

=end
    column(:owner) {|c| c.owner && c.owner.email }
    column :market_id
    column :contest_id
    column(:contest_type){ |c| c.contest_type.try(:name) }
    column :remaining_salary
    column :state
    column :buy_in
    column :takes_tokens
    column :score
    column :contest_rank
    column :amount_paid
    column :paid_at
    column :cancelled_at
    column :submitted_at
    default_actions
  end

end


