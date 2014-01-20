require 'resque/tasks'

namespace :resque do
  desc 'set up redis (is called by redis tasks)'
  task :setup => :environment do
  end
end
