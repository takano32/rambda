#!/usr/bin/env ruby

require 'optparse'
require 'rbconfig'

# deep terms (Church numerals of tens of thousands) recurse deeply, and the
# size of Ruby's VM stack is fixed at startup: restart with a larger one
VM_STACK_SIZE = 256 * 1024 * 1024
if __FILE__ == $0 and ENV['RUBY_THREAD_VM_STACK_SIZE'].nil? then
  begin
    exec({ 'RUBY_THREAD_VM_STACK_SIZE' => VM_STACK_SIZE.to_s }, RbConfig.ruby, __FILE__, *ARGV)
  rescue SystemCallError
  end
end

unless File.exist?(File.join(__dir__, 'lambda.tab.rb'))
  abort "lambda.tab.rb not found: run `rake parser` (or `rake`) to generate it from lambda.y"
end
require_relative 'lambda.tab'
require_relative 'tree'
require_relative 'reducer'


class LambdaExpressionParser < BaseLambdaExpressionParser
end

# prints the reduction of node and returns its normal form, or nil when none was found
def reduce(node, verbose = false, strategy: 'revised', limit: Reducer::LIMIT, eta: false, gc: false,
           quiet: false, church: false, stats: false)
  reducer = Reducer.new(node, strategy: strategy, limit: limit, eta: eta, gc: gc)
  printed = node.to_s
  unless quiet then
    puts ''
    puts '---- reduce ----'
    puts printed
  end
  failed = nil
  begin
    node = reducer.run {|rule, redex, result, term|
      next if quiet
      puts "  #{rule}: #{redex} -> #{result}" if verbose
      puts(printed = term.to_s)
    }
  rescue Reducer::Limit => e
    failed = "#{e.message} (-l raises the limit, -l 0 removes it)"
  rescue Reducer::Cycle => e
    failed = e.message
  rescue Interrupt
    failed = "interrupted after #{reducer.steps} steps"
  end
  if failed then
    puts failed
  else
    # need computes the normal form without showing steps
    result = node.to_s
    puts result if quiet or result != printed
    value = church && Reducer.church(node)
    puts "  = #{value}" if value
  end
  puts "  #{reducer.stats}" if stats
  return failed ? nil : node
end

if __FILE__ == $0 then
  verbose = false
  debug = false
  options = {}
  opts = OptionParser.new
  opts.banner = "Usage: #{File.basename($0)} [options] [file]"
  opts.on('-s', '--strategy NAME', Reducer::STRATEGIES,
          "reduction strategy: #{Reducer::STRATEGIES.join(', ')} (default: revised)") {|s| options[:strategy] = s }
  opts.on('-g', '--gc', 'revised: add the rule gc (&x.E)Q -> E for x not free in E') { options[:gc] = true }
  opts.on('-l', '--limit N', Integer, "give up after N steps (default: #{Reducer::LIMIT}, 0: no limit)") {|n| options[:limit] = n }
  opts.on('-e', '--eta', 'eta-reduce the normal form: &x.(E)x -> E for x not free in E') { options[:eta] = true }
  opts.on('-c', '--church', 'annotate the normal form when it is a Church numeral or boolean') { options[:church] = true }
  opts.on('-q', '--quiet', 'print only the normal form') { options[:quiet] = true }
  opts.on('--stats', 'print the number of steps and the time taken') { options[:stats] = true }
  opts.on('-v', '--verbose', 'show the rule and the redex of each step') { verbose = true }
  opts.on('-d', '--debug', 'show the racc parser trace') { debug = true }
  begin
    opts.parse!(ARGV)
  rescue OptionParser::ParseError => e
    abort "#{e.message}\n#{opts}"
  end

  parser = LambdaExpressionParser.new
  parser.yydebug = debug
  begin
    if ARGV[0] then
      node = File.open( ARGV[0] ) {|f| parser.parse(f) }
    else
      node = parser.parse($stdin)
    end
  rescue Racc::ParseError => e
    abort "parse error: #{e.message.strip}"
  end
  begin
    exit 1 unless reduce(node, verbose, **options)
  rescue SystemStackError
    abort "stack overflow: the term is too deep (try -s need, or a larger RUBY_THREAD_VM_STACK_SIZE)"
  end
end
