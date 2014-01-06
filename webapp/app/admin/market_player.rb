ActiveAdmin.register MarketPlayer do
  filter :market_id
  filter :player_stats_id
  filter :player_name, :as => :string
  filter :player_team, :as => :string


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
    column(:name) {|mp| mp.player && mp.player.name }
    column(:team) {|mp| mp.player && mp.player.team.abbrev }
    column(:initial_shadow_bets) {|mp| mp.initial_shadow_bets.to_i }
    column(:shadow_bets) {|mp| mp.shadow_bets.to_i }
    column(:bets) {|mp| mp.bets.to_i }
    column('$10 price') {|mp| mp.market && mp.price_in_10_dollar_contest }
    column :score
    default_actions

  end

  member_action :market_player_shadow_bets, :method => :post do
    mp = MarketPlayer.find(params[:id])
    initial_bets = mp.bets
    initial_shadow_bets = mp.initial_shadow_bets
  #  self.shadow_bets = self.total_bets = self.initial_shadow_bets = total_bets
    mp.shadow_bets = mp.initial_shadow_bets = mp.bets = params[:shadow_bets].to_i * 100
    mp.save!
    market = mp.market
    market.initial_shadow_bets += mp.shadow_bets - initial_shadow_bets
    market.total_bets += mp.shadow_bets - initial_bets
    market.save!
    redirect_to({:action => :index}, {:notice => "Player's shadow bets updated successfully!"})
  end
  action_item :only => [:show, :edit] do
    form_tag(market_player_shadow_bets_admin_market_player_path(market_player)) do
      text_field_tag('shadow_bets', '', :class => 'custom-text-input', :placeholder => "# shadow bets", :maxlength => 6) + submit_tag("Set Shadow bets")
    end
  end
end


