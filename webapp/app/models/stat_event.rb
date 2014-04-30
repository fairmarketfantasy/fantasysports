class StatEvent < ActiveRecord::Base
  attr_protected

  #I don't think Active Record is going to be saving these records, but what the hell,
  #doesn't hurt to have AR validations that match the database-level constraints
  validates :game_stats_id, :player_stats_id, :point_value, presence: true

  belongs_to :game, :foreign_key => 'game_stats_id', :inverse_of => :stat_events
  # This bullshit doesn't work because the FK doesn't point at the id column
  belongs_to :player, :foreign_key => 'player_stats_id', :inverse_of => :stat_events, :primary_key => :stats_id
  #def player
  #  Player.where(['stats_id = ?', self.player_stats_id])
  #end

  def self.collect_stats(events, position = nil)
    result = {}
    player = events.first.player if events.any?
    last_year = player && player.sport.name == 'MLB' && events.last.game.season_year == Time.now.year - 1
    events_games_count = player.total_games if last_year
    events.each do |event|
      hitters_types = ['Hit By Pitch', 'Doubled', 'Tripled', 'Home Run',
                       'Run Batted In', 'Stolen Base']
      pitchers_types = ['Inning Pitched', 'Strike Out', 'Walked', 'Earned run', 'Wins']
      allowed_types = position && ['SP', 'RP'].include?(position) ? pitchers_types : hitters_types
      next if player.sport.name == 'MLB' && !allowed_types.include?(event.activity)

      key = ['Doubled', 'Tripled'].include?(event.activity) ? 'Extra base hits' : event.activity
      key = key.to_sym

      val = event.quantity.abs
      val = val / events_games_count if last_year
      if result[key]
        result[key] += val
      else
        result[key] = val
      end
    end

    if player && player.sport.name == 'MLB'
      result['Extra base hits'.to_sym] += result['Home Run'.to_sym] if result['Home Run'.to_sym] && result['Extra base hits'.to_sym]
      result['Fantasy Points'] = events.map(&:point_value).reduce(0) { |value, sum| sum + value }*4
    end

    if last_year
      result['Fantasy Points'] = result['Fantasy Points'] / events_games_count
      result['Era (earned run avg)'] = result['Earned run'.to_sym] / events_games_count if result['Earned run'.to_sym]
    end

    result
  end
end
