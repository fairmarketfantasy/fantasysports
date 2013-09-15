namespace :deploy do
  # Put tasks that need to be done at deploy time here
  task :cleanup_html do
    FileUtils.rm Dir.glob(File.join(Rails.root, 'public', 'assets', '*.html'))
  end

  task :do => [:cleanup_html, 'assets:precompile', 'db:setup_functions'] do
    true
  end
end
