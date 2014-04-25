class MLBTeamsFetcherWorker

  include Sidekiq::Worker
  include Sidetiq::Schedulable

  recurrence  do
    minutely(120)
  end

  SPORT_CODE = 'AA' # MLB sport code in The Sports Network API

  sidekiq_options :queue => :mlb_teams_fetcher

  def perform
    page = Nokogiri::HTML open('http://www.sportsnetwork.com/teams.asp')
    text = page.xpath('//h4').first.text
    recent_update_time = Time.strptime text, 'Last Updated:  %m/%d/%Y %H:%M:%S %p %z'
    @recent_mlb_teams_fetch = Sidekiq::Monitor::Job.where(:queue => :mlb_teams_fetcher).last

    # teams info update since the latest fetch time
    if Sidekiq::Monitor::Job.where(:queue => :mlb_teams_fetcher).count == 1 or (@recent_mlb_teams_fetch.started_at and @recent_mlb_teams_fetch.started_at < recent_update_time) or (Team.where(:sport_id => Sport.find_by_name('MLB').id).count == 0)
      # this var may be shared

      # TODO: delete this when release, we mustn`t keep sport without markets
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
          name = data['Name'].downcase.capitalize
          begin
            t = Team.where(sport_id: @sport.id, abbrev: data['Abbr']).first || Team.new
            t.assign_attributes sport: @sport, market: data['Label'], division: data['division'], state: data['State'],
                                abbrev: data['Abbr'], name: name, country: data['Country'], stats_id: data['TeamID'].to_i.to_s
            @matched_abbrevs << data['Abbr']
            t.save!
          rescue => e
            puts 'UNPROCESSED:'
            puts data
            puts e.message
            puts e.backtrace
            counter += 1
          end
        end

      end
      puts "#{counter} unprocessed teams"
    end

    # enqueue fetching players for teams
    Sport.where(:name => 'MLB').first.teams.each do |team|
      PlayersFetcherWorker.perform_async team.stats_id
    end
  end

  def self.job_name
    'Fetching teams for MLB'
  end
end