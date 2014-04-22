class PlayersFetcherWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :players_fetcher

  def perform(team_stats_id)

    @team = Team.find_by_stats_id team_stats_id

    data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/roster?team_id=#{team_stats_id}&year=#{Time.now.year}&api_token=#{TSN_API_KEY}").read

    recent_update_time = Time.parse data['updated_at']
    @recent_players_fetch = Sidekiq::Monitor::Job.where(:queue => :players_fetcher).last
    return if @team.players.count > 0 and Sidekiq::Monitor::Job.where(:queue => :players_fetcher).count > 1 and @recent_players_fetch.started_at and @recent_players_fetch.started_at > recent_update_time

    categories_arr = data['position_categories']
    categories_arr.each do |position_category|
      position_category['listings'].each do |listing|
        player = Player.find_by_stats_id(listing['player_id'].to_s) || Player.new
        player.stats_id = listing['player_id'].to_s
        player.team = @team
        player.sport = @team.sport
        player.name = listing['first_name'] + ' ' + listing['last_name']
        player.name_abbr = listing['last_name']
        player.birthdate = listing['dob']
        player.jersey_number = listing['jersey_number']
        player.status = listing['status']
        player.height = listing['height'].split('-')[0].to_i*30.58 + listing['height'].split('-')[1].to_i*2.54 # convert feets & inches to cm
        player.weight = listing['weight']*0.454 # convert pounds to kilograms
        player.save!
      end
    end

    positions_data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/depth_charts?team_id=#{team_stats_id}&year=#{Time.now.year}&api_token=#{TSN_API_KEY}").read

    strategy = SportStrategy.for(@team.sport.name)

    positions_data['batters'].each do |batter|

      players_ids = [batter['starter_id'], batter['backup_1_id'].presence].compact

      players_ids.each do |player_id|
        player = Player.find_by_stats_id player_id.to_s
        player.positions.map(&:destroy)
        player.update_attribute(:out, true) if batter['backup_1_id'].presence.to_s == player.stats_id

        if strategy.respond_to? :positions_mapper
          players_position = strategy.positions_mapper[batter['position'].upcase]
        else
          players_position = batter['position'].upcase
        end

        PlayerPosition.create! player_id: player.id, position: players_position
      end
    end

    positions_data['starting_pitchers'].each do |starting_pitcher|

      player = Player.find_by_stats_id starting_pitcher['starter_id'].to_s
      player.positions.map(&:destroy)

      PlayerPosition.create! player_id: player.id, position: 'SP'

    end

    positions_data['relief_pitchers'].each do |pitcher|

      player = Player.find_by_stats_id pitcher['starter_id'].to_s
      player.positions.map(&:destroy)

      PlayerPosition.create! player_id: player.id, position: 'RP'

    end
  end

  def self.job_name(team_stats_id)
    @team = Team.find_by_stats_id team_stats_id
    return 'No team found' unless @team

    "Fetch team players for team #{@team.name}"
  end
end