class DataFetcher
  require 'nokogiri'

  NBA_BASE_URL = "http://api.sportsdatallc.org/nba-p3/"
  NBA_API_KEY_PARAMS = "?api_key=8uttxzxefmz45ds8ckz764vr"

  class << self

    def update_benched
      puts "Update benched players"
      url = NBA_BASE_URL + "league/injuries.xml" + NBA_API_KEY_PARAMS
      xml = Nokogiri::XML(open(url))
      players = xml.search("player")
      benched_ids = []
      players.each do |node|
        id = node.xpath("@id").first.value
        status = node.at('injury').at_xpath("@status").value
        if status =~ /^Out/
          benched_ids << id
        elsif status == "Day To Day"
          match = node.at('injury').at_xpath("@comment").value[/\((?<date>\d+\/\d+)\)/, :date]
          if match
            date = Date.strptime("#{match}/#{Date.today.year}", "%m/%d/%Y")
            benched_ids << id if (Time.now.utc - 4.hours).to_date <= date
          else
            benched_ids << id
          end
        end
      end
      sport_id = Sport.where(name: 'NBA').first.id
      Player.where(out: true, sport_id: sport_id).each do |player|
        player.update_attribute(:out, false) unless benched_ids.include?(player.stats_id)
      end
      Player.where(stats_id: benched_ids, sport_id: sport_id).each do |player|
        player.update_attribute(:out, true) unless player.out
      end
    end

    def update_game_players(game)
      puts "Update game players"
      return if game.checked

      url = NBA_BASE_URL + "games/#{game.stats_id}/summary.xml" + NBA_API_KEY_PARAMS
      xml = Nokogiri::XML(open(url))
      second_half_started = xml.search("quarter").find { |node| node.at_xpath("@number").value == "3" }
      return unless second_half_started

      benched_ids = []
      players = xml.search("player")
      players.each do |node|
        id = node.xpath("@id").first.value
        played = node.at_xpath("@played")

        benched_ids << id if played.nil? || played.value != "true"
      end

      game.players.each do |player|
        if benched_ids.include?(player.stats_id)
          Player.where(stats_id: id).first.update_attribute(:out, true) unless player.out
        else
          Player.where(stats_id: id).first.update_attribute(:out, false) if player.out
        end
      end

      game.update_attribute(:checked, true)
    end

  end
end
