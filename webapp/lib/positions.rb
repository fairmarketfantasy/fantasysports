class Positions

  @@positions = {}
  def self.for_sport_id(id)
    if @@positions.empty?
      Sport.all.each do |s|
        @@positions[s.id] = send('default_' + s.name)
      end
    end
    @@positions[id]
  end

  def self.names_for_sport_id(id)
    @@position_names = {}
    if @@position_names.empty?
      Sport.all.each do |s|
        @@position_names[s.id] = send('default_' + s.name + '_names')
      end
    end
    @@position_names[id]
  end

  def self.default_NFL
    'QB,RB,RB,WR,WR,WR,DEF,K,TE'
  end

  def self.default_NFL_names
    'QB,RB,RB,WR,WR,WR,DEF,K,TE'
  end

  def self.default_NBA
    'PG,SG,PF,SF,C,G,F,UTIL'
  end

  def self.default_NBA_names
    'Point Guard,Shooting Guard,Power Forward,Small Forward,Center Forward,Guard Forward,Forward,All'
  end

  def self.default_MLB
    'SP,RP,C,1B/DH,2B,3B,SS,OF,OF,OF'
  end

  def self.default_MLB_names
    'Starting Pitcher,Relief Pitcher,Catcher,First baseman,Second baseman,Third baseman,Shortstop,Outfielder,Outfielder,Outfielder'
  end
end
