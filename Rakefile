require 'rake/testtask'

task :default => :test

Rake::TestTask.new do |t|
  t.libs << 'libs' << 'test'
  t.pattern = 'test/**/*_test.rb'
end
