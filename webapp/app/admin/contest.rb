ActiveAdmin.register Contest do
  filter :start_time
  filter :end_time
  filter :market_id
  filter :paid_at

  index do
    column :id
=begin
id              | integer                     | not null default nextval('contests_id_seq'::regclass)
 owner_id        | integer                     | not null
 buy_in          | integer                     | not null
 user_cap        | integer                     | 
 start_time      | timestamp without time zone | 
 end_time        | timestamp without time zone | 
 created_at      | timestamp without time zone | 
 updated_at      | timestamp without time zone | 
 market_id       | integer                     | not null
 invitation_code | character varying(255)      | 
 contest_type_id | integer                     | not null
 num_rosters     | integer                     | default 0
 paid_at         | timestamp without time zone | 
 private         | boolean                     | default false
=end
    column(:owner) {|c| c.owner && c.owner.email }
    column :start_time
    column :end_time
    column(:contest_type){|c| c.contest_type.name}
    column :buy_in
    column :user_cap
    column :invitation_code
    column :num_rosters
    column :private
    default_actions

  end

end

