ActiveAdmin.register Player do
  actions :all, except: [:destroy]
  filter :name
  filter :position
  filter :team
  filter :sport_id

  index do
    column :id
=begin
 id            | integer                     | not null default nextval('players_id_seq'::regclass)
 stats_id      | character varying(255)      |
 sport_id      | integer                     |
 name          | character varying(255)      |
 name_abbr     | character varying(255)      |
 birthdate     | character varying(255)      |
 height        | integer                     |
 weight        | integer                     |
 college       | character varying(255)      |
 position      | character varying(255)      |
 jersey_number | integer                     |
 status        | character varying(255)      |
 total_games   | integer                     | not null default 0
 total_points  | integer                     | not null default 0
 created_at    | timestamp without time zone |
 updated_at    | timestamp without time zone |
 team          | character varying(255)      |
 benched_games | integer                     | default 0
=end
    column :stats_id
    column :name
    column(:ppg) {|p| p.total_points / (p.total_games + 0.001) }
    column :team
    column :position
    column :status
    column :benched_games
    column :removed
    default_actions

  end

  member_action :mark_active, :method => :get do
    player = Player.find(params[:id])
    player.removed = false
    player.status = 'ACT'
    player.benched_games = 0
    player.save!
    redirect_to({:action => :show}, {:notice => "Player marked active!"})
  end
  member_action :mark_removed, :method => :get do
    player = Player.find(params[:id])
    player.removed = true
    player.status = 'IR'
    player.save!
    redirect_to({:action => :show}, {:notice => "Player marked as removed!"})
  end
   action_item :only => [:show, :edit] do
    link_to('Mark Active', mark_active_admin_player_path(player))
  end
   action_item :only => [:show, :edit] do
    link_to('Mark Benched', mark_removed_admin_player_path(player))
  end
end


