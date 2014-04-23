class GameListener

  include Sidekiq::Worker

  sidekiq_options :queue => :game_listener

  # retry in 1 second
  sidekiq_retry_in do
    1
  end

  def perform(sport = 'mlb')

    EM.run {
      url = "ws://apistream.sportsnetwork.com/v1/#{sport}/play_by_play?team_ids=all"
      puts "Beginning stream to the following url #{url}"

      headers = {'Origin' => 'http://apistream.sportsnetwork.com'}
      ws = Faye::WebSocket::Client.new(url, nil, :headers => headers)

      ws.on :message do |event|
        # here is the entry point for data coming from the server.
        p data = JSON.parse(event.data)
        if data['body']['status'] == 'FINAL' # game finished
          GameStatFetcherWorker.perform_async(data['body']['game_id'].to_s)
        end
      end

      ws.on :close do |event|
        # connection has been closed callback.
        p [:close, event.code, event.reason]
        ws = nil
      end
    }
  end

  def self.job_name(sport = 'mlb')
    'Listening TSN events for sport ' + sport.upcase
  end
end