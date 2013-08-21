namespace :db do
  task :setup_functions => :environment do
    MarketOrder.load_sql_functions
  end
end
