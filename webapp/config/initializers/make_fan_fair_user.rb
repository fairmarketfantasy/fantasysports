email = "fantasysports@mustw.in"
SYSTEM_USER = User.find_or_create_by_email email, :name => "SYSTEM USER", :password => 'F4n7a5y'
