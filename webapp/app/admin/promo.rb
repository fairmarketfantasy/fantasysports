ActiveAdmin.register Promo do
  filter :code
  filter :valid_until

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
    column :code
    column :valid_until
    column(:name) {|mp| mp.player.name }
    column :initial_shadow_bets
    column :shadow_bets
    column :bets
    column('number_of_uses') {|promo| promo.users.count }
    default_actions
  end

end

