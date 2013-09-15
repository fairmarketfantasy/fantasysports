namespace :deploy do
  # Put tasks that need to be done at deploy time here
  task :do => ['assets:clobber', 'assets:precompile', 'db:setup_functions'] do
    true
  end
end
