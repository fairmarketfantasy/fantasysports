namespace :users do
  desc 'Do user accounting'
  task :do_accounting, [:wait_time] => :environment do |t, args|
    File.open(ENV['PIDFILE'], 'w') { |f| f << Process.pid } if ENV['PIDFILE']
  	wait_time = 1.day
  	if not args.wait_time.nil?
  		wait_time = Integer(args.wait_time)
  	end
  	puts "Checking for new month every #{wait_time} seconds"
    CustomerObject.monthly_accounting!
  	while true
      day = Time.new.day
  		print "Is it a new month? Day == #{day} - "
      if day == 1
  		  puts "Yup.  Performing accounting."
        CustomerObject.monthly_accounting!
      else
  		  puts "Nope. Sleeping."
      end
	  	sleep wait_time
  	end
  end
end
