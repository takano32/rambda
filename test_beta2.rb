#!/usr/bin/env ruby
require 'test/unit'
require 'test/unit/assertions'
require 'lambda'
require 'stringio'

class TestLambdaExpressionParser < Test::Unit::TestCase
  def setup
    @parser = LambdaExpressionParser.new
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

  def _test_reduce(src)
    puts ''
    puts '---- reduce test ----'
    sio = StringIO.new(src)
    node = @parser.parse(sio)
    puts node.to_s
    marked = false
    while( marked || node.mark_first_redex(true) ) do
      node, marked = node.reduce
      puts node.to_s
    end
  end

  def test_church
    zero = '&f.&x.x'
    #one = '&f.&x.(f)x'
    succ = '&n.&f.&x.(f)((n)f)x'
    _test_reduce("(#{succ})#{zero}")
  end

  def test_reduce1
    _test_reduce('(q)((&y.p)r)(&y.y)r')
    # (q)(p)(&y.y)r
    # (q)(p)r
  end
  
  def test_reduce2
    _test_reduce('(&y.(q)(p)y)r')
  end

  def test_reduce3
    _test_reduce('(&y.(x)y)&x.(u)x')
  end

  def test_beta()
    src = '(((&f.&x.&y.(x)(f)y)p)q)r'
    src = '((&x.&y.(y)x)3)f'
    _test_reduce(src)
  end

  def _test_beta(i, src, dest)
    sio = StringIO.new(src)
    node = @parser.parse(sio)
    assert(node.mark_first_redex)
    assert_equal(dest, node.beta(i).to_s)
  end

  def test_alpha
    src = '(&x.&y.x)y'
    _test_reduce(src)
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




