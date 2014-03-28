class MLBTeamsFetcherWorker

  include Sidekiq::Worker

  SPORT_CODE = 'AA' # MLB sport code in The Sports Network API

  sidekiq_options :queue => :mlb_teams_fetcher

  def perform
    page = Nokogiri::HTML open('http://www.sportsnetwork.com/teams.asp')
    text = page.xpath('//h4').first.text
    recent_update_time = Time.strptime text, 'Last Updated:  %m/%d/%Y %H:%M:%S %p %z'
    @recent_mlb_teams_fetch = Sidekiq::Monitor::Job.where(:queue => :mlb_teams_fetcher).last

    # teams info update since the latest fetch time
    if Sidekiq::Monitor::Job.where(:queue => :mlb_teams_fetcher).count == 1 or @recent_mlb_teams_fetch.started_at < recent_update_time
      # this var may be shared

      # TODO: delete this when release, we mustn`t keep sport without markets
      begin
        s = Sport.new
        s.name = 'MLB'
        s.is_active = true
        s.playoffs_on = true
        s.save
      rescue
      end

      @sport = Sport.where(:name => 'MLB').first

      @matched_abbrevs = []
      
      doc = Nokogiri::XML open('http://www.sportsnetwork.com/teams3.asp').read
      nodes = doc.xpath('//teams/Listing')
      counter = 0
      nodes.each do |node|
        basenode = node.child
        data = {}
        while basenode do
          if basenode.text.lstrip.present?
            data[basenode.name] = basenode.child.text
          end

          basenode = basenode.next
        end

        if !(@matched_abbrevs.include? data['Abbr']) and data['sportcode'] == SPORT_CODE and data['TeamID'].to_i <= 60 and data['TeamID'].to_i > 0 # parse 1-60 items
          name = data['Fullname'] ? data['Fullname'] : data['Name']
          begin
            t = Team.find_by_sport_id_and_abbrev(@sport.id, data['Abbr']) || Team.new
            t.assign_attributes sport: @sport, market: data['Label'], division: data['division'], state: data['State'],
                                abbrev: data['Abbr'], name: name, country: data['Country'], stats_id: data['TeamID']
            @matched_abbrevs << data['Abbr']
            t.save!
          rescue
            puts 'UNPROCESSED:'
            puts data
            puts t.errors.full_messages
            counter += 1
          end
        end

      end
      puts "#{counter} unprocessed teams"

      # enqueue fetching players for teams
      @matched_abbrevs.each { |abbr| PlayersFetcherWorker.perform_async abbr }
    end
  end

  def self.job_name
    'Fetching teams for MLB'
  end
end