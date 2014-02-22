require 'rake/testtask'
require 'rubygems'
require 'rubygems/package_task'

task :default => :test

gemspec = Gem::Specification::load(File.expand_path('../docurium.gemspec', __FILE__))
Gem::PackageTask.new(gemspec) do |pkg|
end

Rake::TestTask.new do |t|
  t.libs << 'libs' << 'test'
  t.pattern = 'test/**/*_test.rb'
end
