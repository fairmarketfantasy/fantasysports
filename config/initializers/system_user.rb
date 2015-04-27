SYSTEM_USER = begin
  User.find_by_email "fantasysports@mustw.in" 
rescue 
  nil
end
Rails.logger.warn "=" * 50 + "\nSystem user not installed. Run `rake db:seed`\n" + "=" * 50 unless SYSTEM_USER

