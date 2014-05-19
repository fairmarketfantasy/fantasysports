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
