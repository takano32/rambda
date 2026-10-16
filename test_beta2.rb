#!/usr/bin/env ruby
require_relative 'test_helper'
require 'tempfile'

# the revised rules of tree.rb, reduced step by step as lambda.rb does by default
class TestLambdaExpressionParser < Test::Unit::TestCase
  include LambdaTestHelper
  LIMIT = 100000

  def setup
    @parser = LambdaExpressionParser.new
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

  # the normal form of src is alpha-equivalent to expected
  def assert_alpha_equal(expected, src)
    super(expected, reduce(src), "#{src} ->")
  end

  def test_variables
    sio = StringIO.new('(λx y. E) Q')
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
    assert_equal([VariableNode.new('y')], parse('(λy. y) y').variables)
    assert_equal(%w[y x z], parse('(λx. x y) x (λy. z)').variables.map(&:to_s))
    assert_equal(%w[x x y y x y], parse('(λx. x y) ((λy. x y) 3)').all_variables.map(&:to_s))
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
    zero = 'λf x. x'
    #one = 'λf x. f x'
    succ = 'λn f x. f (n f x)'
    assert_equal('λf x. f x', normal_form("(#{succ}) (#{zero})"))
  end

  def test_reduce1
    assert_equal('q (p r)', normal_form('q ((λy. p) r ((λy. y) r))'))
    # q (p ((λy. y) r))
    # q (p r)
  end

  def test_reduce2
    assert_equal('q (p r)', normal_form('(λy. q (p y)) r'))
  end

  def test_reduce3
    assert_equal('x (λx. u x)', normal_form('(λy. x y) (λx. u x)'))
  end

  def test_beta()
    assert_equal('q (p r)', normal_form('(λf x y. x (f y)) p q r'))
    assert_equal('f 3', normal_form('(λx y. y x) 3 f'))
  end

  # the redex is in the argument of an application whose function part is not a redex
  def test_redex_in_argument
    assert_equal('x y w', normal_form('x y ((λz. z) w)'))
    assert_equal('x (y w)', normal_form('x (y ((λz. z) w))'))
    assert_equal('λx. x w', normal_form('λx. x ((λz. z) w)'))
  end

  # (λx. c) Q -> c for a constant c, too
  def test_beta2_constant
    assert_equal('3', normal_form('(λx. 3) Q'))
    assert_equal('3 y', normal_form('(λx. 3 x) y'))
  end

  def _test_beta(i, src, dest)
    sio = StringIO.new(src)
    node = @parser.parse(sio)
    assert(node.mark_first_redex)
    assert_equal(dest, node.beta(i).to_s)
  end

  def test_alpha
    assert_equal('λa. y', normal_form('(λx y. x) y'))
  end

  # each step reports the rule, the redex and its result; after alpha
  # the renaming (λy. E) z is finished before the outer beta4
  def test_reduce_steps
    steps = []
    node = reduce('(λx y. x) y', steps)
    assert_equal('λa. y', node.to_s)
    assert_equal([['alpha', 'λy. x', 'λa. (λy. x) a', '(λx a. (λy. x) a) y'],
                  ['beta2', '(λy. x) a', 'x', '(λx a. x) y'],
                  ['beta4', '(λx a. x) y', 'λa. (λx. x) y', 'λa. (λx. x) y'],
                  ['beta1', '(λx. x) y', 'y', 'λa. y']], steps)
    steps = []
    reduce('q ((λy. p) r ((λy. y) r))', steps)
    assert_equal([['beta2', '(λy. p) r', 'p', 'q (p ((λy. y) r))'],
                  ['beta1', '(λy. y) r', 'r', 'q (p r)']], steps)
  end

  # the fresh variable must not occur in the argument
  def test_alpha_fresh_variable
    assert_equal('λy. a y', normal_form('(λx y. x y) a'))
    assert_equal('λb. a y b', normal_form('(λx y. x y) (a y)'))
    assert_equal('λc. a (b y) c', normal_form('(λx y. x y) (a (b y))'))
  end

  # nor in the body being renamed
  def test_alpha_fresh_variable_in_body
    assert_equal('λb. y b a', normal_form('(λx y. x y a) y'))
    assert_equal('λb a. y b', normal_form('(λx y a. x y) y'))
    assert_alpha_equal('λz a. y z', '(λx y a. x y) y')
  end

  # free variables of the argument must not be captured
  def test_alpha_capture_in_argument
    assert_equal('λa. y', normal_form('(λx y. x) ((λy. y) y)'))
    assert_equal('λa. y a', normal_form('(λx y. x y) ((λy. y) y)'))
  end

  # fresh variables are not limited to a..z
  def test_alpha_fresh_variable_fallback
    body = (('a'..'z').to_a - %w[x y]).inject('x') {|t, v| "#{t} #{v}" }
    assert_equal("λa1. #{body.sub('x', 'y')}", normal_form("(λx y. #{body}) y"))
    body = (('a'..'z').to_a - %w[x y]).inject('x a1') {|t, v| "#{t} #{v}" }
    assert_equal("λb1. #{body.sub('x', 'y')}", normal_form("(λx y. #{body}) y"))
  end

  # beta5 duplicates the argument: reducing one copy must leave the other alone
  def test_beta5_copies_argument
    steps = []
    node = reduce('(λx. x x) (w ((λy. y) z))', steps)
    assert_equal('w z (w z)', node.to_s)
    assert_equal(['w ((λy. y) z) (w ((λy. y) z))', 'w z (w ((λy. y) z))', 'w z (w z)'],
                 steps.map {|s| s[3] }.last(3))
  end

  def test_builtins
    zero = 'λf x. x'
    one = 'λf x. f x'
    two = 'λf x. f (f x)'
    three = 'λf x. f (f (f x))'
    assert_alpha_equal('λx y. x', '#{true}')
    assert_alpha_equal('λx y. y', '#{false}')
    assert_alpha_equal(one, "\#{succ} (#{zero})")
    assert_alpha_equal(two, "\#{succ} (#{one})")
    assert_alpha_equal(two, "+ (#{one}) (#{one})")
    assert_alpha_equal(three, "+ (#{one}) (#{two})")
    assert_alpha_equal(zero, "* (#{zero}) (#{two})")
    assert_alpha_equal(two, "* (#{one}) (#{two})")
    assert_alpha_equal('λf x. f (f (f (f (f (f x)))))', "* (#{two}) (#{three})")
    assert_alpha_equal('λx y. x', "\#{zero} (#{zero})")
    assert_alpha_equal('λx y. y', "\#{zero} (#{one})")
    assert_alpha_equal('λx y. y', "\#{zero} (#{two})")
    assert_alpha_equal(zero, "\#{pred} (#{zero})")
    assert_alpha_equal(zero, "\#{pred} (#{one})")
    assert_alpha_equal(one, "\#{pred} (#{two})")
    assert_alpha_equal(one, "\#{pred} (\#{succ} (\#{succ} (#{zero})))")
  end

  # λ and \, merged binders, left associative application, an abstraction as
  # the last argument, primes; let is a keyword only on its own
  def test_lambda_syntax
    assert_equal('λx y. y x', parse('λx.λy.y x').to_s)
    assert_equal('λx y. y x', parse('\x.\y.y x').to_s)
    assert_equal('λx y. y x', parse('λx y. y x').to_s)
    assert_equal('(λx. x) 3', parse("( \\x .\n x ) 3\n").to_s)
    assert_equal('f x y', parse('(f x) y').to_s)
    assert_equal('f (x y)', parse('f (x y)').to_s)
    assert_equal('λx. x (λy. y x) z', parse('λx. x (λy. y x) z').to_s)
    assert_equal('f (λx. x y)', parse('f λx. x y').to_s)
    assert_equal('f x (λy z. y z)', parse('f x \y z. y z').to_s)
    assert_equal("x' (y'' let')", parse("x' (y'' let')").to_s)
    assert_raise(Racc::ParseError) { parse('(λx.x') }
    assert_raise(Racc::ParseError) { parse('λx') }
    assert_raise(Racc::ParseError) { parse('λ. x') }
    assert_raise(Racc::ParseError) { parse('f λx') }
    assert_raise(Racc::ParseError) { parse('&x.x') }
    assert_raise(Racc::ParseError) { parse('#{foo}') }
  end

  # the fewest parentheses: an abstraction is parenthesized when applied or
  # an argument, an application when an argument
  def test_to_s
    assert_equal('x y z', parse('((x y) z)').to_s)
    assert_equal('x (y z)', parse('x (y z)').to_s)
    assert_equal('f (g x) y', parse('f (g x) y').to_s)
    assert_equal('(λx. x) y', parse('(λx. x) y').to_s)
    assert_equal('y (λx. x)', parse('y λx. x').to_s)
    assert_equal('(λx. x) (λy. y) z', parse('(λx. x) (λy. y) z').to_s)
    assert_equal('λx y. x', parse('λx. λy. x').to_s)
    assert_equal('λx. (λy. y) x', parse('λx. (λy. y) x').to_s)
    assert_equal('λx. x (λy. y) 3', parse('λx. x (λy. y) 3').to_s)
    assert_equal('(λx. x x) (λx. x x)', parse('#{Omega}').to_s)
    assert_equal('λ.λ.#1 (#1 #0)', parse('λf x. f (f x)').canonical)
    assert_equal('(λ.#0 #0) (λ.#0 #0) y', parse('#{Omega} y').canonical)
  end

  # --ascii prints \ for λ
  def test_to_s_ascii
    LambdaExpressionNode.lambda = '\\'
    assert_equal('(\x y. x) (\z. z)', parse('(λx y. x) λz. z').to_s)
  ensure
    LambdaExpressionNode.lambda = 'λ'
  end

  # parsing the output of to_s gives the same tree, for every shape of term
  def test_to_s_round_trip
    random = Random.new(2026)
    names = %w[x y z f' g1]
    gen = lambda {|depth|
      case (depth <= 0 ? random.rand(2) : random.rand(5))
      when 0 then VariableNode.new(names[random.rand(names.size)])
      when 1 then ConstantNode.new(random.rand(10))
      when 2 then AbstractionNode.new(VariableNode.new(names[random.rand(names.size)]), gen.call(depth - 1))
      else ApplicationNode.new(gen.call(depth - 1), gen.call(depth - 1))
      end
    }
    1000.times {
      term = gen.call(5)
      src = term.to_s
      node = parse(src)
      assert_same_tree(term, node, src)
      assert_equal(src, node.to_s)
      assert_equal(term.canonical, node.canonical, src)
    }
  end

  def test_parse_is_quiet
    err, $stderr = $stderr, StringIO.new
    begin
      parse('#{pred} ((λx y. x) y)')
      assert_equal('', $stderr.string)
    ensure
      $stderr = err
    end
  end

  def test_cli
    expected = "\n---- reduce ----\n(λx y. x) y\n(λx a. (λy. x) a) y\n(λx a. x) y\nλa. (λx. x) y\nλa. y\n"
    assert_equal(expected, run_lambda(:input => '(λx y. x) y'))
    Tempfile.create('lambda') {|f|
      f.puts '(λx y. x) y'
      f.close
      assert_equal(expected, run_lambda(f.path))
      verbose = run_lambda('-v', f.path)
      assert_include(verbose, "\n  alpha: λy. x -> λa. (λy. x) a\n(λx a. (λy. x) a) y\n")
      assert_include(verbose, "\n  beta1: (λx. x) y -> y\nλa. y\n")
      assert_equal(expected.lines, verbose.lines.reject {|l| l.start_with?('  ') })
      # λ is read and written as UTF-8 whatever the locale says
      assert_equal(expected, run_lambda(f.path, env: { 'LANG' => 'C', 'LC_ALL' => 'C' }))
    }
    assert_equal(expected, run_lambda(:input => '(λx y. x) y', env: { 'LANG' => 'C', 'LC_ALL' => 'C' }))
    assert_equal(expected.tr('λ', '\\'), run_lambda('--ascii', :input => '(\x y. x) y'))
    assert_include(run_lambda('-d', :input => '(λx. x) y'), 'shift')
    assert_include(run_lambda(:input => '(λx.x'), 'parse error')
  end

  def test_beta1
    _test_beta(1, '(λx. x) Q', 'Q')
  end

  def test_beta2
    _test_beta(2, '(λx. y) Q', 'y')
  end

  def test_beta3
    _test_beta(3, '(λx x. E) Q', 'λx. E')
  end

  def test_beta4
    _test_beta(4, '(λf x y. x (f y)) p', 'λx. (λf y. x (f y)) p')
  end

  def test_beta5
    _test_beta(5, '(λx. E1 E2) Q', '(λx. E1) Q ((λx. E2) Q)')
  end
end
