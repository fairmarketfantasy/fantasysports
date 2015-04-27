namespace :migration do
  namespace :jan_2014 do
    desc "populate new player position table"
    task :populate_positions => :environment do
      Player.all.each do |p|
        PlayerPosition.create!(:player_id => p.id, :position => p.position)
      end
    end
  end
end
