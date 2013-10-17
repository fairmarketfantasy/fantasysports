ActiveAdmin.register Market do
  filter :state
  filter :closed_at
  config.sort_order = "closed_at_asc"

  index do
    column :id
=begin
    id                  | integer                     | not null default nextval('markets_id_seq'::regclass)
     name                | character varying(255)      | 
        shadow_bets         | numeric                     | not null
      shadow_bet_rate     | numeric                     | not null
       opened_at           | timestamp without time zone | 
          closed_at           | timestamp without time zone | 
           created_at          | timestamp without time zone | 
            updated_at          | timestamp without time zone | 
             published_at        | timestamp without time zone | 
              state               | character varying(255)      | 
               total_bets          | numeric                     | 
                sport_id            | integer                     | not null
        initial_shadow_bets | numeric                     | 
           price_multiplier    | numeric                     | default 1
         started_at          | timestamp without time zone | 
=end
    column :name
    column :started_at
    column :opened_at
    column :closed_at
    column :state
    column :total_bets
    column :shadow_bets
    column :price_multiplier
    default_actions

  end

  member_action :player_download do
    filename = 'market_players_' + params[:id] + '.csv'
    headers.merge!({
      'Cache-Control'             => 'must-revalidate, post-check=0, pre-check=0',
      'Content-Type'              => 'application/octet-stream',
      'Content-Disposition'       => "attachment; filename=\"market_players_#{params[:id]}.csv\"",
      'Content-Transfer-Encoding' => 'binary'
    })
    send_data Market.find(params[:id]).dump_players_csv, :filename => filename, :type => 'text/csv'
  end

  member_action :player_upload, :method => :post do
    market = Market.find(params[:id])
    market.import_players_csv(params[:players].read)
    redirect_to({:action => :index}, {:notice => "CSV imported successfully!"})
  end

   action_item :only => [:show, :edit] do
    link_to('Download players', player_download_admin_market_path(market))
  end
  action_item :only => [:show, :edit] do
    form_tag(player_upload_admin_market_path(market), multipart: true) do
      file_field_tag('players') + submit_tag("Import players")
    end if market.closed_at > Time.now
  end
end
