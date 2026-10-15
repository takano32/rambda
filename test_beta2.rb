#!/usr/bin/env ruby
require 'test/unit'
require_relative 'lambda'
require 'stringio'
require 'tempfile'
require 'rbconfig'

class TestLambdaExpressionParser < Test::Unit::TestCase
  LIMIT = 100000
  LAMBDA_RB = File.join(__dir__, 'lambda.rb')

  def setup
    @parser = LambdaExpressionParser.new
  end

  def parse(src)
    return @parser.parse(StringIO.new(src))
  end

  # reduce src to its normal form, recording [rule, redex, result, term] of each step
  def reduce(src, steps = nil)
    node = parse(src)
    count = 0
    while node.mark_first_redex do
      node, rule, redex, result = node.reduce
      steps << [rule, redex.to_s, result.to_s, node.to_s] if steps
      count += 1
      flunk "#{src}: no normal form after #{LIMIT} steps" if count > LIMIT
    end
    return node
  end

  def normal_form(src)
    return reduce(src).to_s
  end

  # bound variables as de Bruijn indices, for comparison up to alpha
  def debruijn(node, env = [])
    case node
    when AbstractionNode
      "&.#{debruijn(node.expr, [node.var.to_s] + env)}"
    when ApplicationNode
      "(#{debruijn(node.expr1, env)})#{debruijn(node.expr2, env)}"
    when VariableNode
      i = env.index(node.to_s)
      i ? "##{i}" : node.to_s
    else
      node.to_s
    end
  end

  def assert_alpha_equal(expected, src)
    assert_equal(debruijn(parse(expected)), debruijn(reduce(src)), "#{src} ->")
  end

  def run_lambda(*args, input: nil)
    IO.popen([RbConfig.ruby, LAMBDA_RB, *args], 'r+', :err => [:child, :out]) {|io|
      io.write(input) if input
      io.close_write
      io.read
    }
  end

  def test_variables
    sio = StringIO.new('(&x.&y.E)Q')
    node = @parser.parse(sio)
    variables = []
    #variables << VariableNode.new('x')
    #variables << VariableNode.new('y')
    variables << VariableNode.new('E')
    variables << VariableNode.new('Q')
    assert_equal(variables, node.variables)
  end

  # a binder must not hide free occurrences outside its scope
  def test_variables_scope
    assert_equal([VariableNode.new('y')], parse('(&y.y)y').variables)
    assert_equal(%w[y x z], parse('((&x.(x)y)x)&y.z').variables.map(&:to_s))
    assert_equal(%w[x x y y x y], parse('(&x.(x)y)(&y.(x)y)3').all_variables.map(&:to_s))
  end

  def test_constant_equality
    assert_equal(ConstantNode.new(3), ConstantNode.new(3))
    assert_not_equal(ConstantNode.new(3), ConstantNode.new(4))
    assert_false(ConstantNode.new(3) == VariableNode.new('x'))
    assert_false(VariableNode.new('x') == ConstantNode.new(3))
    assert_false(ConstantNode.new(3) == nil)
    assert_true([ConstantNode.new(3)].include?(ConstantNode.new(3)))
    assert_false([VariableNode.new('x')].include?(ConstantNode.new(3)))
    assert_equal(1, [VariableNode.new('x'), VariableNode.new('x')].uniq.size)
    assert_equal(1, [ConstantNode.new(3), ConstantNode.new(3)].uniq.size)
    assert_equal(ConstantNode.new(3).hash, ConstantNode.new(3).hash)
  end

  def test_church
    zero = '&f.&x.x'
    #one = '&f.&x.(f)x'
    succ = '&n.&f.&x.(f)((n)f)x'
    assert_equal('&f.&x.(f)x', normal_form("(#{succ})#{zero}"))
  end

  def test_reduce1
    assert_equal('(q)(p)r', normal_form('(q)((&y.p)r)(&y.y)r'))
    # (q)(p)(&y.y)r
    # (q)(p)r
  end

  def test_reduce2
    assert_equal('(q)(p)r', normal_form('(&y.(q)(p)y)r'))
  end

  def test_reduce3
    assert_equal('(x)&x.(u)x', normal_form('(&y.(x)y)&x.(u)x'))
  end

  def test_beta()
    assert_equal('(q)(p)r', normal_form('(((&f.&x.&y.(x)(f)y)p)q)r'))
    assert_equal('(f)3', normal_form('((&x.&y.(y)x)3)f'))
  end

  # the redex is in the argument of an application whose function part is not a redex
  def test_redex_in_argument
    assert_equal('((x)y)w', normal_form('((x)y)(&z.z)w'))
    assert_equal('(x)(y)w', normal_form('(x)(y)(&z.z)w'))
    assert_equal('&x.(x)w', normal_form('&x.(x)(&z.z)w'))
  end

  # (&x.c)Q -> c for a constant c, too
  def test_beta2_constant
    assert_equal('3', normal_form('(&x.3)Q'))
    assert_equal('(3)y', normal_form('(&x.(3)x)y'))
  end

  def _test_beta(i, src, dest)
    sio = StringIO.new(src)
    node = @parser.parse(sio)
    assert(node.mark_first_redex)
    assert_equal(dest, node.beta(i).to_s)
  end

  def test_alpha
    assert_equal('&a.y', normal_form('(&x.&y.x)y'))
  end

  # each step reports the rule, the redex and its result; after alpha
  # the renaming (&y.E)z is finished before the outer beta4
  def test_reduce_steps
    steps = []
    node = reduce('(&x.&y.x)y', steps)
    assert_equal('&a.y', node.to_s)
    assert_equal([['alpha', '&y.x', '&a.(&y.x)a', '(&x.&a.(&y.x)a)y'],
                  ['beta2', '(&y.x)a', 'x', '(&x.&a.x)y'],
                  ['beta4', '(&x.&a.x)y', '&a.(&x.x)y', '&a.(&x.x)y'],
                  ['beta1', '(&x.x)y', 'y', '&a.y']], steps)
    steps = []
    reduce('(q)((&y.p)r)(&y.y)r', steps)
    assert_equal([['beta2', '(&y.p)r', 'p', '(q)(p)(&y.y)r'],
                  ['beta1', '(&y.y)r', 'r', '(q)(p)r']], steps)
  end

  # the fresh variable must not occur in the argument
  def test_alpha_fresh_variable
    assert_equal('&y.(a)y', normal_form('(&x.&y.(x)y)a'))
    assert_equal('&b.((a)y)b', normal_form('(&x.&y.(x)y)(a)y'))
    assert_equal('&c.((a)(b)y)c', normal_form('(&x.&y.(x)y)(a)(b)y'))
  end

  # nor in the body being renamed
  def test_alpha_fresh_variable_in_body
    assert_equal('&b.((y)b)a', normal_form('(&x.&y.((x)y)a)y'))
    assert_equal('&b.&a.(y)b', normal_form('(&x.&y.&a.(x)y)y'))
    assert_alpha_equal('&z.&a.(y)z', '(&x.&y.&a.(x)y)y')
  end

  # free variables of the argument must not be captured
  def test_alpha_capture_in_argument
    assert_equal('&a.y', normal_form('(&x.&y.x)(&y.y)y'))
    assert_equal('&a.(y)a', normal_form('(&x.&y.(x)y)(&y.y)y'))
  end

  # fresh variables are not limited to a..z
  def test_alpha_fresh_variable_fallback
    body = (('a'..'z').to_a - %w[x y]).inject('x') {|t, v| "(#{t})#{v}" }
    assert_equal("&a1.#{body.sub('x', 'y')}", normal_form("(&x.&y.#{body})y"))
    body = (('a'..'z').to_a - %w[x y]).inject('(x)a1') {|t, v| "(#{t})#{v}" }
    assert_equal("&b1.#{body.sub('x', 'y')}", normal_form("(&x.&y.#{body})y"))
  end

  # beta5 duplicates the argument: reducing one copy must leave the other alone
  def test_beta5_copies_argument
    steps = []
    node = reduce('(&x.(x)x)(w)(&y.y)z', steps)
    assert_equal('((w)z)(w)z', node.to_s)
    assert_equal(['((w)(&y.y)z)(w)(&y.y)z', '((w)z)(w)(&y.y)z', '((w)z)(w)z'],
                 steps.map {|s| s[3] }.last(3))
  end

  def test_builtins
    zero = '&f.&x.x'
    one = '&f.&x.(f)x'
    two = '&f.&x.(f)(f)x'
    three = '&f.&x.(f)(f)(f)x'
    assert_alpha_equal('&x.&y.x', '#{true}')
    assert_alpha_equal('&x.&y.y', '#{false}')
    assert_alpha_equal(one, "(#{'#{succ}'})#{zero}")
    assert_alpha_equal(two, "(#{'#{succ}'})#{one}")
    assert_alpha_equal(two, "((+)#{one})#{one}")
    assert_alpha_equal(three, "((+)#{one})#{two}")
    assert_alpha_equal(zero, "((*)#{zero})#{two}")
    assert_alpha_equal(two, "((*)#{one})#{two}")
    assert_alpha_equal('&f.&x.(f)(f)(f)(f)(f)(f)x', "((*)#{two})#{three}")
    assert_alpha_equal('&x.&y.x', "(#{'#{zero}'})#{zero}")
    assert_alpha_equal('&x.&y.y', "(#{'#{zero}'})#{one}")
    assert_alpha_equal('&x.&y.y', "(#{'#{zero}'})#{two}")
    assert_alpha_equal(zero, "(#{'#{pred}'})#{zero}")
    assert_alpha_equal(zero, "(#{'#{pred}'})#{one}")
    assert_alpha_equal(one, "(#{'#{pred}'})#{two}")
    assert_alpha_equal(one, "(#{'#{pred}'})(#{'#{succ}'})(#{'#{succ}'})#{zero}")
  end

  def test_lambda_syntax
    assert_equal('&x.&y.(y)x', parse('\x.\y.(y)x').to_s)
    assert_equal('(&x.x)3', parse("( \\x .\n x ) 3\n").to_s)
    assert_raise(Racc::ParseError) { parse('(&x.x') }
    assert_raise(Racc::ParseError) { parse('#{foo}') }
  end

  def test_parse_is_quiet
    err, $stderr = $stderr, StringIO.new
    begin
      parse('(#{pred})(&x.&y.x)y')
      assert_equal('', $stderr.string)
    ensure
      $stderr = err
    end
  end

  def test_cli
    expected = "\n---- reduce ----\n(&x.&y.x)y\n(&x.&a.(&y.x)a)y\n(&x.&a.x)y\n&a.(&x.x)y\n&a.y\n"
    assert_equal(expected, run_lambda(:input => '(&x.&y.x)y'))
    Tempfile.create('lambda') {|f|
      f.puts '(&x.&y.x)y'
      f.close
      assert_equal(expected, run_lambda(f.path))
      verbose = run_lambda('-v', f.path)
      assert_include(verbose, "\n  alpha: &y.x -> &a.(&y.x)a\n(&x.&a.(&y.x)a)y\n")
      assert_include(verbose, "\n  beta1: (&x.x)y -> y\n&a.y\n")
      assert_equal(expected.lines, verbose.lines.reject {|l| l.start_with?('  ') })
    }
    assert_include(run_lambda('-d', :input => '(&x.x)y'), 'shift')
    assert_include(run_lambda(:input => '(&x.x'), 'parse error')
  end

  def test_beta1
    _test_beta(1, '(&x.x)Q', 'Q')
  end

  def test_beta2
    _test_beta(2, '(&x.y)Q', 'y')
  end

  def test_beta3
    _test_beta(3, '(&x.&x.E)Q', '&x.E')
  end

  def test_beta4
    _test_beta(4, '(&f.&x.&y.(x)(f)y)p', '&x.(&f.&y.(x)(f)y)p')
  end

  def test_beta5
    _test_beta(5, '(&x.(E1)E2)Q', '((&x.E1)Q)(&x.E2)Q')
  end
end




