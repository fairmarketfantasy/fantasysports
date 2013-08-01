set :stage_name, 'production'
set :rails_env, 'production'

server "54.225.100.119", :app, :web, :primary => true     # Your HTTP server

after 'deploy:update_code' do
  # Compile assets
  #run "cd #{release_path}; RAILS_ENV=production rake assets:precompile"
end

