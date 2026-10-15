require 'rake/testtask'
require 'rake/clean'

PARSER = 'lambda.tab.rb'
CLEAN.include(PARSER)

def racc
  Gem.bin_path('racc', 'racc')
rescue LoadError, Gem::Exception
  'racc'
end

file PARSER => 'lambda.y' do |t|
  ruby racc, '-g', '-o', t.name, t.prerequisites.first
end

desc "generate #{PARSER} from lambda.y"
task :parser => PARSER

Rake::TestTask.new(:test) do |t|
  t.test_files = ['test_beta2.rb']
end
task :test => PARSER

task :default => :test
