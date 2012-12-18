require 'rake/testtask'
Rake::TestTask.new(:minitest) do |test|
  test.test_files = FileList["spec/**/*.rb"]
  test.verbose = false
  test.warning = false
end

task :default => [:minitest]