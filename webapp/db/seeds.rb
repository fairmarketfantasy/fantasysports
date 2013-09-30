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
    co.stripe_id = "blah" if Rails.env == 'test'
    co.save!
  rescue => e
    puts "ERROR CREATING SYSTEM USER CUSTOMER OBJECT. NO MONEY WILL BE COLLECTED: #{e.message}"
  end
end

#add NFL to sports
Sport.where(:name => "NFL").first_or_create.save
