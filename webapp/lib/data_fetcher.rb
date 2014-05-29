class DataFetcher
  require 'nokogiri'

  NBA_BASE_URL = "http://api.sportsdatallc.org/nba-p3/"
  NBA_API_KEY_PARAMS = "?api_key=8uttxzxefmz45ds8ckz764vr"

  class << self

    def update_benched
      puts "Update benched players"
      url = NBA_BASE_URL + "league/injuries.xml" + NBA_API_KEY_PARAMS
      xml = get_xml(url)
      players = xml.search("player")
      benched_ids = []
      players.each do |node|
        id = node.xpath("@id").first.value
        status = node.at('injury').at_xpath("@status").value
        benched_ids << id if status =~ /^Out/
      end

      sport_id = Sport.where(name: 'NBA').first.id
      Player.where(stats_id: benched_ids, sport_id: sport_id).each do |player|
        player.update_attribute(:out, true) unless player.out
      end
    end

    def update_game_players(game, required_time = nil)
      return if game.sport.name == 'MLB'

      puts "Update game players"
      url = NBA_BASE_URL + "games/#{game.stats_id}/summary.xml" + NBA_API_KEY_PARAMS
      xml = get_xml(url)
      second_half_started = xml.search("quarter").find { |node| node.at_xpath("@number").value == "3" }
      return unless second_half_started

      benched_ids = []
      game_player_ids = []
      players = xml.search("player")
      players.each do |node|
        id = node.xpath("@id").first.value
        game_player_ids << id
        played = node.at_xpath("@played")

        benched_ids << id if played.nil? || played.value != "true" || less_then_n_min(node, required_time)
      end

      return if (game_player_ids.sort - benched_ids.sort).empty?
      game.players.each do |player|
        if benched_ids.include?(player.stats_id) || !game_player_ids.include?(player.stats_id)
          player.update_attribute(:out, true) unless player.out
        else
          player.update_attribute(:out, false) if player.out
        end
      end

      game.update_attribute(:checked, true)
    end

    def calculate_teams_pt(game)
      url = 'http://97.74.80.137/SportsOddsAPI/Odds/5Dimes/MLB'
      odds = JSON.parse open(url).read
      odd = odds.find do |odd|
        game.game_time == DateTime.strptime(odd["GameTime"], '%m/%d/%Y %l:%M %p')
        game.home_team == find_team(odd["Home"]).stats_id
        game.away_team == find_team(odd["Visitor"]).stats_id
      end

      return unless odd

      home_ml = odd["HomeMoneyLine"].to_d
      away_ml = odd["VisitorMoneyLine"].to_d
      game.home_team_pt = DataFetcher.get_pt_value(home_ml, away_ml)
      game.away_team_pt = DataFetcher.get_pt_value(away_ml, home_ml)
      game.save!
    end

    def find_team(team_name)
      category = Category.where(name: 'fantasy_sports').first
      sport = Sport.where(name: 'MLB', category_id: category.id).first
      team = Team.where(sport_id: sport.id, market: team_name).first
      team ||= Team.where(sport_id: sport.id).find do |t|
        t.name.downcase.include?(team_name.split(/\s+/).last.downcase)
      end

      team ||= Team.where(sport_id: sport.id).find do |t|
        t.market.downcase.include?(team_name.split(/\s+/).first.downcase)
      end

      team || raise("Team not found!")
    end

    def get_pt_value(target_ml, opposite_ml)
      total_ml = (target_ml.abs + opposite_ml.abs).to_d/2
      return 15.to_d if total_ml == 0

      prob = if target_ml > opposite_ml
               100/(100 + total_ml)
             else
               1-100/(100 + total_ml)
             end

      value = 1/prob * 0.95 * Roster::FB_CHARGE * 10
      value.round
    end

    private

    def get_xml(url)
      attempts = 0
      begin
        Nokogiri::XML(open(url))
      rescue
        sleep(1)
        attempts += 1
        retry if attempts <= 5
      end
    end

    def less_then_n_min(node, required_time)
      return unless required_time

      minutes = node.search("statistics").at_xpath("@minutes")
      points = node.search("statistics").at_xpath("@points")

      min_val = minutes.value.split(":")[0..-2].join("") if minutes
      return true unless min_val

      min_val.to_i <= required_time
    end

  end
end
