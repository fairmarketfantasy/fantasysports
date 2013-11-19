ActiveAdmin.register MarketPlayer do
  filter :market_id
  filter :player_stats_id

  index do
    column :id
=begin
 market_id           | integer                     | not null
 player_id           | integer                     | not null
 shadow_bets         | numeric                     |
 bets                | numeric                     | default 0
 locked_at           | timestamp without time zone |
 initial_shadow_bets | numeric                     |
 locked              | boolean                     | default false
 score               | integer                     | not null default 0
 player_stats_id     | character varying(255)      |
=end
    column :market_id
    column :player_id
    column :player_stats_id
    column(:name) {|mp| mp.player.name }
    column :initial_shadow_bets
    column :shadow_bets
    column :bets
    column :score
    default_actions

  end

end


