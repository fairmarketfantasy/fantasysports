# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

#system user
email = "fantasysports@mustw.in"
SYSTEM_USER = User.where(:email => email, :name => "SYSTEM USER").first_or_create
SYSTEM_USER.password = 'F4n7a5y'
SYSTEM_USER.save
co = CustomerObject.where(:user_id => SYSTEM_USER.id).first
if co.nil?
  begin
    co = CustomerObject.new(:user_id => SYSTEM_USER.id, :balance => 0)
    co.save!
  rescue => e
    puts "ERROR CREATING SYSTEM USER CUSTOMER OBJECT. NO MONEY WILL BE COLLECTED: #{e.message}"
  end
end

#adds sports
Sport.where(:name => "NFL").first_or_create.save
Sport.where(:name => "NBA").first_or_create.save
Sport.where(:name => "MLB").first_or_create.save
MarketDefaults.where(:sport_id => 0).first_or_create(:single_game_multiplier => 2.3, :multiple_game_multiplier => 10).save

CATEGORY_SPORTS = { 'fantasy_sports' => ['nfl', 'nba', 'mlb'],
                    'entertainment' => ['music', 'reality shows', 'oscars', 'grammys', 'celebrity propositions'],
                    'politics' => ['presidental candidates', 'congressional races', 'snt'],
                    'sports' => ['mlb', 'fwc', 'nhl', 'nascar', 'golf', 'tennis', 'hrd'] }

CATEGORY_SPORTS.each do |category, sports|
  cat = Category.where(name: category).first_or_create!
  if category == 'sports'
    cat.update_attribute(:note, '')
  elsif category == 'fantasy_sports'
    cat.update_attribute(:note, '')
  end

  sports.each do |s|
    if category == 'fantasy_sports'
      sport = Sport.where(name: s.upcase).first
      sport.update_attributes(category_id: cat.id, coming_soon: false) unless cat.sports.where(name: s.upcase).first
    else
      sport = cat.sports.where(name: s.upcase).first_or_create!
      sport.update_attribute(:coming_soon, false) if sport.name == 'MLB' or sport.name == 'FWC'
    end
  end
end

inactive_sport_names = ['MUSIC', 'REALITY SHOWS', 'OSCARS', 'GRAMMYS', 'CELEBRITY PROPOSITIONS',
                        'PRESIDENTAL CANDIDATES', 'CONGRESSIONAL RACES', 'NASCAR',
                        'GOLF', 'TENNIS']
Sport.where(name: inactive_sport_names).each { |s| s.update_attribute(:is_active, false) }
Category.where(name: 'entertainment').each { |s| s.update_attribute(:is_active, false) }
Category.where(name: 'politics').each { |s| s.update_attribute(:is_active, true) }
Category.where(name: 'sports').first.sports.where(name: ['NFL', 'NHL', 'NBA']).each do |s|
  s.update_attribute(:is_active, false)
end

Sport.all.each do |s|
  name  = if s.name == 'FWC'
            'Soccer World Cup 2014'
          elsif s.name == 'MLB' && s.category.name == 'sports'
            'Predict-a-Game MLB'
          elsif s.name == 'HRD' && s.category.name == 'sports'
            'Home run derby'
          elsif s.name == 'SNT' && s.category.name == 'politics'
            'Senate races'
          else
            s.name
          end
  s.update_attribute(:title, name)
end

Category.all.each do |s|
  name = s.name.gsub('_', ' ')
  s.update_attribute(:title, name)
end

Category.where(name: 'sports').first.update_attribute(:is_new, true)

fwc_sport = Sport.where(:name => 'FWC').first
cup_competition = fwc_sport.competitions.where(name: 'Win the cup').first_or_create!
fwc_sport.teams.each do |t|
  Member.where(competition_id: cup_competition.id, memberable_id: t.id,
               memberable_type: 'Team').first_or_create!
end

fwc_sport.groups.each do |group|
  group_competition = fwc_sport.competitions.where(name: group.name).first_or_create!
  group.teams.each do |t|
    Member.where(competition_id: group_competition.id, memberable_id: t.id,
                 memberable_type: 'Team').first_or_create!
  end
end

mvp_competition = fwc_sport.competitions.where(name: 'MVP').first_or_create!
fwc_sport.players.each do |p|
  Member.where(competition_id: mvp_competition.id, memberable_id: p.id,
               memberable_type: 'Player').first_or_create!
end
