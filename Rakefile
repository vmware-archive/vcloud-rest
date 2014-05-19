require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |test|
  test.verbose = false
  test.rspec_opts = "--format documentation --color"
end

task :default => [:spec]