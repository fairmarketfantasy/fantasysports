namespace :db do
  task :setup_functions => :environment do
    Market.load_sql_functions
  end
end
