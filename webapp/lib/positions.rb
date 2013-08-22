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

  def self.default_NFL
    'QB,RB,RB,WR,WR,WR,DEF,K,TE'
  end
end
