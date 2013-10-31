# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'docurium/version'

Gem::Specification.new do |s|
  s.name        = "docurium"
  s.version     = Docurium::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Carlos Martín Nieto", "Scott Chacon"]
  s.email       = ["cmn@dwim.me", "schacon@gmail.com"]
  s.homepage    = "https://github.com/libgit2/docurium"
  s.summary     = "A simpler, prettier Doxygen replacement."
  s.description = s.summary

  s.rubyforge_project = 'docurium'

  s.add_dependency "version_sorter", "~>1.1.0"
  s.add_dependency "mustache", ">= 0.99.4"
  s.add_dependency "rocco", "~>0.8"
  s.add_dependency "gli", "~>2.5"
  s.add_dependency "rugged", "~>0.19"
  s.add_dependency "redcarpet", "~>3.0"
  s.add_development_dependency "bundler",   "~>1.0"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end

