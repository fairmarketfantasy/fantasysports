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
                    'politics' => ['presidental candidates', 'congressional races', 'senate races'],
                    'sports' => ['mlb', 'nba', 'nfl', 'nhl', 'nascar', 'golf', 'tennis'] }

CATEGORY_SPORTS.each do |category, sports|
  cat = Category.where(name: category).first_or_create
  if category == 'sports'
    cat.update_attribute(:note, '')
  elsif category == 'fantasy_sports'
    cat.update_attribute(:note, '')
  end

  sports.each.each do |s|
    if category == 'fantasy_sports'
      sport = Sport.where(name: s.upcase).first
      sport.update_attributes(category_id: cat.id, coming_soon: false) unless cat.sports.where(name: s.upcase).first
    else
      sport = cat.sports.where(name: s.upcase).first_or_create
      sport.update_attribute(:coming_soon, false) if sport.name == 'MLB'
    end
  end
end
