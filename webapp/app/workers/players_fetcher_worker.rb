class PlayersFetcherWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :players_fetcher

  def perform(team_abbrev)

    @team = Team.find team_abbrev
    team_id = @team.stats_id
    data = JSON.parse open("http://api.sportsnetwork.com/v1/mlb/roster?team_id=#{team_id}&year=#{Time.now.year}&api_token=#{TSN_API_KEY}").read

    recent_update_time = Time.parse data['updated_at']
    @recent_players_fetch = Sidekiq::Monitor::Job.where(:queue => :players_fetcher).last
    return if @team.players.count > 0 and Sidekiq::Monitor::Job.where(:queue => :players_fetcher).count > 1 and @recent_players_fetch.started_at > recent_update_time

    categories_arr = data['position_categories']
    categories_arr.each do |position_category|
      position_category['listings'].each do |listing|
        player = Player.find_by_stats_id(listing['player_id'].to_s) || Player.new
        player.stats_id = listing['player_id'].to_s
        player.team = @team
        player.sport = @team.sport
        player.name = listing['first_name'] + ' ' + listing['last_name']
        player.name_abbr = listing['first_name']
        player.birthdate = listing['dob']
        player.jersey_number = listing['jersey_number']
        player.status = listing['status']
        player.height = listing['height'].split('-')[0].to_i*30.58 + listing['height'].split('-')[1].to_i*2.54 # convert feets & inches to cm
        player.weight = listing['weight']*0.454 # convert pounds to kilograms
        player.save!

        # recreate positions
        player.positions.map(&:destroy)
        PlayerPosition.create! player_id: player.id, position: listing['position']
      end
    end
  end

  def self.job_name(team_abbrev)
    @team = Team.find team_abbrev
    return 'No team found' unless @team

    "Fetch team players for team #{@team.name}"
  end
end