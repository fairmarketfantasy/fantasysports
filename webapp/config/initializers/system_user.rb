SYSTEM_USER = User.find_by_email "fantasysports@mustw.in"
Rails.logger.warn "=" * 50 + "\nSystem user not installed. Run `rake db:seed`\n" + "=" * 50 unless SYSTEM_USER

