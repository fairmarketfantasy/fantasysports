class DataFetcher
  require 'nokogiri'

  NBA_BASE_URL = "http://api.sportsdatallc.org/nba-p3/"
  NBA_API_KEY_PARAMS = "?api_key=8uttxzxefmz45ds8ckz764vr"

  def self.update_benched
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
end
