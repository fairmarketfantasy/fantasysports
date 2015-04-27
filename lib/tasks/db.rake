namespace :db do
  task :setup_functions => :environment do
    Market.load_sql_functions
  end


  namespace :backup do
    BACKUP_NAME = '/tmp/db_backup.sql.gz'
    desc 'create a backup for the database'
    task :create => :environment do
      yaml = YAML.load_file(File.join(Rails.root, 'config', 'database.yml'))[Rails.env]
      AWS_ACCESS_KEY="AKIAJXV4UPD3IV4JK6DA"
      AWS_SECRET_KEY="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"
      `PGPASSWORD=#{yaml['password']} pg_dump -h #{yaml['host']} -U #{yaml["username"]} #{yaml['database']} | gzip > #{BACKUP_NAME}`
    end

    desc 'upload the db backup to s3'
    task :upload => :environment do
      now = Time.new
      file = "backup/#{now.year}/#{now.month}-#{now.day}@#{now.hour}:#{now.min}:#{now.sec}.sql.gz"
      bucket = AWS::S3.new.buckets[S3_BUCKET]
      bucket.objects[file].write(open(BACKUP_NAME))
    end

    desc 'clean up the backups'
    task :cleanup do
      File.delete()
    end

    desc 'create a backup for the database'
    task :do => ['db:backup:create', 'db:backup:upload', 'db:backup:cleanup'] do
    end
  end
end
