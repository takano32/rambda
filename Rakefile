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
  t.test_files = %w[test_beta2.rb test_reducer.rb]
end
task :test => PARSER

desc 'compare the strategies on Church numeral workloads (Markdown table)'
task :bench => PARSER do
  ruby 'bench.rb'
end

task :default => :test
