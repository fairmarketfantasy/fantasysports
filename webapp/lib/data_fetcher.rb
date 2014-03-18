class DataFetcher
  require 'nokogiri'

  NBA_BASE_URL = "http://api.sportsdatallc.org/nba-p3/"
  NBA_API_KEY_PARAMS = "?api_key=8uttxzxefmz45ds8ckz764vr"

  def self.update_benched
    puts "Update benched players"
    url = NBA_BASE_URL + "league/injuries.xml" + NBA_API_KEY_PARAMS
    xml = Nokogiri::XML(open(url))
    players = xml.search("player")
    benched_ids = players.map { |node| node.xpath("@id").first.value }
    sport_id = Sport.where(name: 'NBA').first.id

    Player.where(out: true, sport_id: sport_id).each do |player|
      player.update_attribute(:out, false) unless benched_ids.include?(player.stats_id)
    end

    Player.where(stats_id: benched_ids, sport_id: sport_id).each do |player|
      player.update_attribute(:out, true) unless player.out
    end
  end
end
