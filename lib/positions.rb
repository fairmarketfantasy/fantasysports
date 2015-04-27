class Positions

  @@positions = {}

  def self.for_sport_id(id)
    if @@positions.empty? and not Sport.find(id).coming_soon?
      Sport.all.each do |s|
        @@positions[s.id] = send('default_' + s.name)
      end
    end
    @@positions[id]
  end

  def self.names_for_sport_id(id)
    @@position_names = {}
    if @@position_names.empty?
      Category.where(name: 'fantasy_sports').first.sports.each do |s|
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
    'SP,C,1B/DH,2B,3B,SS,OF,OF,OF'
  end

  def self.default_MLB_names
    'Starting Pitcher,Catcher,First baseman,Second baseman,Third baseman,Shortstop,Outfielder,Outfielder,Outfielder'
  end

  (Sport.all.map(&:name) - %w(NFL NBA MLB')).each do |item|
    self.class.send :define_method, "default_#{item}" do
      ''
    end
  end

  (Sport.all.map(&:name) - %w(NFL NBA MLB')).each do |item|
    self.class.send :define_method, "default_#{item}" do
      ''
    end
  end
end
