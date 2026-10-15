require 'test/unit'
require_relative 'lambda'
require 'stringio'
require 'rbconfig'

module LambdaTestHelper
  LAMBDA_RB = File.join(__dir__, 'lambda.rb')

  def parse(src)
    return LambdaExpressionParser.new.parse(StringIO.new(src))
  end

  # the Church numeral n
  def church(n)
    return '&f.&x.' + '(f)' * n + 'x'
  end

  # node (or source) is alpha-equivalent to the term of expected (source)
  def assert_alpha_equal(expected, node, message = nil)
    node = parse(node) if node.is_a?(String)
    assert_equal(parse(expected).canonical, node.canonical, message)
  end

  # runs lambda.rb and returns its output (stdout and stderr); $? is its status
  def run_lambda(*args, input: nil)
    IO.popen([RbConfig.ruby, LAMBDA_RB, *args], 'r+', :err => [:child, :out]) {|io|
      io.write(input) if input
      io.close_write
      io.read
    }
  end
end
