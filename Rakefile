require 'rake'

begin

  require 'jeweler'

  FileList['tasks/**/*.rake'].each { |task| load task }

  Jeweler::Tasks.new do |gem|

    gem.name        = "dm-is-awesome_set"
    gem.summary     = %Q{A nested set plugin for datamapper}
    gem.description = %Q{A library that lets any datamapper model act like a nested set}
    gem.email       = "jnicoll@gnexp.com"
    gem.homepage    = "http://github.com/snusnu/dm-is-awesome_set"
    gem.authors     = ["Jeremy Nicoll", "David Haslem", "Martin Gamsjaeger (snusnu)"]

  end

  Jeweler::GemcutterTasks.new

rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

task :default => :spec
