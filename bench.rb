#!/usr/bin/env ruby
# Church numeral workloads under each strategy, as a Markdown table of the
# steps taken and the wall time (revised: rule applications, with the number
# of beta reductions in parentheses).
#   ruby bench.rb [seconds per cell (default 60)]

require_relative 'lambda'
require 'stringio'
require 'timeout'

PRELUDE = <<~'EOS'
  let Y = &f.(&x.(f)(x)x)&x.(f)(x)x;
  let zero = &f.&x.x;
  let one = &f.&x.(f)x;
  let two = &f.&x.(f)(f)x;
  let three = &f.&x.(f)(f)(f)x;
  let four = &f.&x.(f)(f)(f)(f)x;
  let five = &f.&x.(f)(f)(f)(f)(f)x;
  let ten = ((+)five)five;
  let fact = (Y)&g.&n.(((#{zero})n)one)((*)n)(g)(#{pred})n;
  let fib = (Y)&g.&n.(((#{zero})n)zero)(((#{zero})(#{pred})n)one)((+)(g)(#{pred})n)(g)(#{pred})(#{pred})n;
EOS

WORKLOADS = [
  ['succ 0', '(#{succ})zero', 1],
  ['2 + 3', '((+)two)three', 5],
  ['3 * 4', '((*)three)four', 12],
  ['2 ^ 5', '(five)two', 32],
  ['2 ^ 10', '(ten)two', 1024],
  ['pred 10', '(#{pred})ten', 9],
  ['fact 3', '(fact)three', 6],
  ['fact 4', '(fact)four', 24],
  ['fact 5', '(fact)five', 120],
  ['fib 5', '(fib)five', 5],
  ['fib 10', '(fib)ten', 55],
]

STRATEGIES = [
  ['revised', {}],
  ['revised -g', { gc: true }],
  ['normal', { strategy: 'normal' }],
  ['need', { strategy: 'need' }],
]

SECONDS = (ARGV[0] || 60).to_f

def cell(src, expected, options)
  node = LambdaExpressionParser.new.parse(StringIO.new(PRELUDE + src))
  reducer = Reducer.new(node, limit: 0, **options)
  begin
    nf = Timeout.timeout(SECONDS) { reducer.run }
  rescue Timeout::Error
    return "> #{SECONDS.round}s"
  end
  raise "#{src}: #{nf} is not #{expected}" unless Reducer.church(nf) == expected.to_s
  steps = reducer.steps.to_s
  steps << " (#{reducer.beta})" if reducer.strategy == 'revised'
  return "#{steps} / #{'%.3f' % reducer.time}s"
end

puts "| | #{STRATEGIES.map {|name, _| name }.join(' | ')} |"
puts "| --- | #{STRATEGIES.map { '---:' }.join(' | ')} |"
WORKLOADS.each {|name, src, expected|
  puts "| #{name} | #{STRATEGIES.map {|_, options| cell(src, expected, options) }.join(' | ')} |"
  $stdout.flush
}
