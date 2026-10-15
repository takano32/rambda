#!/usr/bin/env ruby

require 'optparse'

unless File.exist?(File.join(__dir__, 'lambda.tab.rb'))
  abort "lambda.tab.rb not found: run `rake parser` (or `rake`) to generate it from lambda.y"
end
require_relative 'lambda.tab'
require_relative 'tree'


class LambdaExpressionParser < BaseLambdaExpressionParser
end

def reduce(node, verbose = false)
  puts ''
  puts '---- reduce ----'
  puts node.to_s
  while node.mark_first_redex do
    node, rule, redex, result = node.reduce
    puts "  #{rule}: #{redex} -> #{result}" if verbose
    puts node.to_s
  end
  return node
end

if __FILE__ == $0 then
  verbose = false
  debug = false
  opts = OptionParser.new
  opts.banner = "Usage: #{File.basename($0)} [-v] [-d] [file]"
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
  reduce(node, verbose)
end

