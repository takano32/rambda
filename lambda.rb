#!/usr/bin/env ruby

require 'lambda.tab'
require 'tree'


class LambdaExpressionParser < BaseLambdaExpressionParser
end

def reduce(node)
  puts ''
  puts '---- reduce ----'
  puts node.to_s
  marked = false
  while( marked || node.mark_first_redex(true) ) do
    node, marked = node.reduce
    puts node.to_s
  end
end

if __FILE__ == $0 then
  parser = LambdaExpressionParser.new
  if ARGV[0] then
    File.open( ARGV[0] ) {|f|
      puts parser.parse(f)
    }
  else
    node = parser.parse($stdin)
    reduce(node)
  end
end

