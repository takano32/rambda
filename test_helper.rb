require 'test/unit'
require_relative 'lambda'
require 'stringio'
require 'rbconfig'

module LambdaTestHelper
  LAMBDA_RB = File.join(__dir__, 'lambda.rb')

  def parse(src)
    return LambdaExpressionParser.new.parse(StringIO.new(src))
  end

  # the Church numeral n, as to_s prints it
  def church(n)
    return n == 0 ? 'λf x. x' : 'λf x. ' + 'f (' * (n - 1) + 'f x' + ')' * (n - 1)
  end

  # node (or source) is alpha-equivalent to the term of expected (source)
  def assert_alpha_equal(expected, node, message = nil)
    node = parse(node) if node.is_a?(String)
    assert_equal(parse(expected).canonical, node.canonical, message)
  end

  # node is the same tree as expected, binder names included
  def assert_same_tree(expected, node, message = nil)
    assert_equal(expected.class, node.class, message)
    case expected
    when ApplicationNode
      assert_same_tree(expected.expr1, node.expr1, message)
      assert_same_tree(expected.expr2, node.expr2, message)
    when AbstractionNode
      assert_equal(expected.var, node.var, message)
      assert_same_tree(expected.expr, node.expr, message)
    else
      assert_equal(expected, node, message)
    end
  end

  # runs lambda.rb and returns its output (stdout and stderr); $? is its status
  def run_lambda(*args, input: nil, env: {})
    IO.popen(env, [RbConfig.ruby, LAMBDA_RB, *args], 'r+', :err => [:child, :out]) {|io|
      io.write(input) if input
      io.close_write
      io.read
    }
  end
end
