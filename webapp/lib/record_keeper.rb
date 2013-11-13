class RecordKeeper
  def self.for_league
    # stub
  end

  def self.for_roster(roster)
    if roster.contest_type.name == 'h2h rr'
      RoundRobinRecordKeeper.new(roster)
    else
      RecordKeeperBase.new(roster)
    end
  end

end

class RecordKeeperBase
  def initialize(roster)
    @roster = roster
    @n_winners = @roster.contest.num_winners
  end

  def wins
    @roster.contest_rank <= @n_winners ? 1 : 0
  end

  def losses
    @roster.contest_rank > @n_winners ? 1 : 0
  end

  def ties
    0
  end

  def total_games
    1
  end
end

class RoundRobinRecordKeeper < RecordKeeperBase
  def wins
    total_games - losses - ties
  end

  def ties
    @ties ||= @roster.contest.rosters.map(&:contest_rank).select{|r| r == @roster.contest_rank }.count - 1
  end

  def losses
    @losses ||= @roster.contest_rank - 1
  end

  def total_games
   @roster.contest.num_rosters
  end
end
