ActiveAdmin.register Contest do
  actions :all, except: [:destroy]
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
    column(:market_name) {|c| c.market && c.market.name }
    #column :start_time
    #column :end_time
    column(:contest_type){|c| c.contest_type.name }
    column(:league){|c| c.league && c.league.name }
    column(:date) { |c| c.market.games.last.game_day }
    column :invitation_code
    column :num_rosters
    column :num_generated
    column :private
    column :rosters do |contest|
      link_to "Rosters", :controller => "rosters", :action => "index", 'q[contest_id_eq]' => "#{contest.id}".html_safe
    end
    default_actions

  end

end

