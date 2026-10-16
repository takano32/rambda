#!/usr/bin/env ruby
require_relative 'test_helper'
require 'tempfile'

# the strategies of reducer.rb, and the options of lambda.rb
class TestReducer < Test::Unit::TestCase
  include LambdaTestHelper

  MODES = {
    'revised' => { strategy: 'revised' },
    'gc' => { strategy: 'revised', gc: true },
    'normal' => { strategy: 'normal' },
    'need' => { strategy: 'need' },
  }
  LIMIT = 300_000
  OMEGA = '(&x.(x)x)&x.(x)x'

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

  # [normal form, reducer] of src under the mode
  def reduce(src, mode = 'revised', **options, &block)
    reducer = Reducer.new(parse(src), limit: LIMIT, **MODES[mode], **options)
    return reducer.run(&block), reducer
  end

  def normal_form(src, mode = 'revised', **options)
    return reduce(src, mode, **options).first
  end

  # Church numeral workloads for every mode, and heavier ones for the fast modes
  WORKLOADS = {
    '(#{succ})zero' => 1,
    '((+)two)three' => 5,
    '((*)three)four' => 12,
    '(three)two' => 8,
    '(two)three' => 9,
    '(#{pred})three' => 2,
    '(#{pred})zero' => 0,
    '(fact)three' => 6,
  }
  HEAVY = {
    '(fib)five' => 5,
    '(fact)four' => 24,
    '(ten)two' => 1024,
    '(#{pred})ten' => 9,
  }

  def test_workloads
    MODES.each_key {|mode|
      WORKLOADS.each {|src, n|
        nf = normal_form(PRELUDE + src, mode)
        assert_alpha_equal(church(n), nf, "#{src} (#{mode})")
        assert_equal(n == 0 ? '0 (false)' : n.to_s, Reducer.church(nf), "#{src} (#{mode})")
      }
    }
  end

  def test_workloads_heavy
    %w[normal need].each {|mode|
      HEAVY.each {|src, n|
        assert_alpha_equal(church(n), normal_form(PRELUDE + src, mode), "#{src} (#{mode})")
      }
    }
    assert_alpha_equal(church(120), normal_form(PRELUDE + '(fact)five', 'need'))
    assert_alpha_equal(church(55), normal_form(PRELUDE + '(fib)ten', 'need'))
  end

  # every built-in, by the Church numeral or boolean of its result
  BUILTINS = {
    '#{0}' => '0 (false)', '#{3}' => '3',
    '((#{exp})#{2})#{3}' => '8', '((#{sub})#{5})#{2}' => '3', '((#{sub})#{2})#{5}' => '0 (false)',
    '((#{plus})#{2})#{3}' => '5', '((#{mult})#{2})#{3}' => '6', '(#{iszero})#{0}' => 'true',
    '((#{leq})#{2})#{3}' => 'true', '((#{leq})#{3})#{2}' => '0 (false)',
    '((#{lt})#{2})#{3}' => 'true', '((#{lt})#{3})#{3}' => '0 (false)',
    '((#{eq})#{3})#{3}' => 'true', '((#{eq})#{3})#{2}' => '0 (false)',
    '(#{not})#{true}' => '0 (false)', '((#{and})#{true})#{false}' => '0 (false)',
    '((#{or})#{false})#{true}' => 'true', '((#{xor})#{true})#{true}' => '0 (false)',
    '((#{xor})#{true})#{false}' => 'true', '(((#{if})#{true})#{1})#{2}' => '1',
    '(#{fst})((#{pair})#{1})#{2}' => '1', '(#{snd})((#{pair})#{1})#{2}' => '2',
    '(#{head})(#{tail})((#{cons})#{1})((#{cons})#{2})#{nil}' => '2',
    '(#{null})#{nil}' => 'true', '(#{null})((#{cons})#{1})#{nil}' => '0 (false)',
    '(#{I})#{7}' => '7', '(((#{S})#{K})#{K})#{4}' => '4', '(((#{B})#{succ})#{succ})#{1}' => '3',
    '(((#{C})#{sub})#{1})#{4}' => '3', '((#{W})#{plus})#{3}' => '6',
  }
  FIX = {
    '((#{Y})&g.&n.(((#{zero})n)#{1})((*)n)(g)(#{pred})n)#{4}' => '24',
    '((#{Z})&g.&n.((((#{zero})n)&d.#{1})&d.((*)n)(g)(#{pred})n)#{I})#{4}' => '24',
  }

  def test_builtins
    MODES.each_key {|mode|
      BUILTINS.each {|src, expected|
        assert_equal(expected, Reducer.church(normal_form(src, mode)), "#{src} (#{mode})")
      }
    }
    %w[normal need].each {|mode|
      FIX.each {|src, expected|
        assert_equal(expected, Reducer.church(normal_form(src, mode)), "#{src} (#{mode})")
      }
    }
    assert_alpha_equal('(&x.(x)x)&x.(x)x', '#{Omega}')
    assert_raise(Reducer::Cycle) { normal_form('#{Omega}') }
    assert_raise(Racc::ParseError) { parse('#{foo}') }
  end

  def test_booleans
    MODES.each_key {|mode|
      assert_equal('true', Reducer.church(normal_form('(#{zero})&f.&x.x', mode)), mode)
      assert_equal('0 (false)', Reducer.church(normal_form('(#{zero})&f.&x.(f)x', mode)), mode)
    }
  end

  # the normal forms of test_beta2.rb, up to alpha, in every mode
  CAPTURE = {
    '(&x.&y.x)y' => '&a.y',
    '(&x.&y.(x)y)a' => '&y.(a)y',
    '(&x.&y.(x)y)(a)y' => '&b.((a)y)b',
    '(&x.&y.((x)y)a)y' => '&b.((y)b)a',
    '(&x.&y.&a.(x)y)y' => '&b.&a.(y)b',
    '(&x.&y.x)(&y.y)y' => '&a.y',
    '(&x.&y.(x)y)(&y.y)y' => '&a.(y)a',
    '(&x.&y.&z.((x)y)z)(y)z' => '&a.&b.(((y)z)a)b',
    '(&x.(x)x)(w)(&y.y)z' => '((w)z)(w)z',
    '(&x.&x.x)y' => '&x.x',
    '(&y.&x.x)x' => '&x.x',
    '(&x.(&y.&x.(x)y)x)z' => '&a.(a)z',
    '(&f.&x.(f)x)&x.(x)x' => '&x.(x)x',
  }

  def test_capture
    MODES.each_key {|mode|
      CAPTURE.each {|src, expected|
        assert_alpha_equal(expected, normal_form(src, mode), "#{src} (#{mode})")
      }
    }
  end

  # need keeps the binder names unless they would capture a free variable
  def test_need_names
    assert_equal('&x.x', normal_form('(&y.&x.x)x', 'need').to_s)
    assert_equal('&x.&x.x', normal_form('&x.&x.x', 'need').to_s)
    assert_equal('&a.y', normal_form('(&x.&y.x)y', 'need').to_s)
    assert_equal('&b.((a)y)b', normal_form('(&x.&y.(x)y)(a)y', 'need').to_s)
    assert_equal('&f.&x.(f)(f)(f)(f)(f)(f)x', normal_form(PRELUDE + '((*)two)three', 'need').to_s)
    assert_equal('&a.&b.(((y)z)a)b', normal_form('(&x.&y.&z.((x)y)z)(y)z', 'need').to_s)
  end

  # arguments that have no normal form are left alone when they are not needed
  def test_normal_order
    MODES.each_key {|mode|
      assert_equal('y', normal_form("(&x.y)#{OMEGA}", mode).to_s, mode)
      assert_alpha_equal('&y.y', normal_form("(&x.&y.y)#{OMEGA}", mode), mode)
      assert_alpha_equal(church(1), normal_form("((&x.&y.x)#{church(1)})#{OMEGA}", mode), mode)
      assert_alpha_equal('&f.(f)x', normal_form("&f.(f)(&y.x)#{OMEGA}", mode), mode)
    }
  end

  def test_cycle
    %w[revised gc normal].each {|mode|
      e = assert_raise(Reducer::Cycle, mode) { normal_form(OMEGA, mode) }
      assert_match(/\Ano normal form: the term repeats itself \(cycle detected at step \d+\)\z/, e.message)
      # a cycle of length 2
      assert_raise(Reducer::Cycle, mode) { normal_form('((&x.&y.((x)x)y)&x.&y.((x)x)y)z', mode) }
      # a cycle after a few steps
      assert_raise(Reducer::Cycle, mode) { normal_form("(&y.(y)(y)x)&x.#{OMEGA}", mode) }
    }
    # need cannot see a cycle: the limit stops it
    e = assert_raise(Reducer::Limit) { normal_form(OMEGA, 'need', limit: 100) }
    assert_equal(100, e.steps)
  end

  def test_limit
    growing = '(&f.(&x.(f)(x)x)&x.(f)(x)x)g'
    MODES.each_key {|mode|
      e = assert_raise(Reducer::Limit, mode) { normal_form(growing, mode, limit: 50) }
      assert_equal('no normal form within 50 steps', e.message)
      assert_equal(50, e.steps)
      assert_alpha_equal(church(5), normal_form(PRELUDE + '((+)two)three', mode, limit: 0), mode)
    }
    assert_equal('y', normal_form('(&x.x)y', 'normal', limit: 1).to_s)
    e = assert_raise(Reducer::Limit) { normal_form('(&x.x)(&x.x)y', 'normal', limit: 1) }
    assert_equal('no normal form within 1 step', e.message)
  end

  def test_eta
    MODES.each_key {|mode|
      assert_equal('f', normal_form('&x.(f)x', mode, eta: true).to_s, mode)
      assert_equal('&x.(f)x', normal_form('&x.(f)x', mode).to_s, mode)
      assert_equal('&x.(x)x', normal_form('&x.(x)x', mode, eta: true).to_s, mode)
      assert_equal('f', normal_form('&x.&y.((f)x)y', mode, eta: true).to_s, mode)
      assert_equal('f', normal_form('(&y.&x.(y)x)f', mode, eta: true).to_s, mode)
      assert_equal('g', normal_form('&x.(&y.(g)y)x', mode, eta: true).to_s, mode)
      assert_equal('&x.(f)(x)x', normal_form('&x.(f)(x)x', mode, eta: true).to_s, mode)
      assert_equal('(f)g', normal_form('(f)&x.(g)x', mode, eta: true).to_s, mode)
    }
    steps = []
    nf, reducer = reduce('&x.&y.((f)x)y', 'normal', eta: true) {|*step| steps << step.map(&:to_s) }
    assert_equal('f', nf.to_s)
    assert_equal([['eta', '&y.((f)x)y', '(f)x', '&x.(f)x'], ['eta', '&x.(f)x', 'f', 'f']], steps)
    assert_equal({ 'eta' => 2 }, reducer.counts)
    assert_equal(2, reducer.steps)
    assert_equal(0, reducer.beta)
  end

  def test_church
    assert_equal('0 (false)', Reducer.church(parse('&f.&x.x')))
    assert_equal('1', Reducer.church(parse('&f.&x.(f)x')))
    assert_equal('3', Reducer.church(parse('&g.&y.(g)(g)(g)y')))
    assert_equal('true', Reducer.church(parse('&x.&y.x')))
    assert_nil(Reducer.church(parse('&x.x')))
    assert_nil(Reducer.church(parse('&f.&x.(x)f')))
    assert_nil(Reducer.church(parse('&f.&x.(f)(g)x')))
    assert_nil(Reducer.church(parse('&f.&f.(f)f')))
    assert_nil(Reducer.church(parse('&f.&x.&y.(f)x')))
    assert_nil(Reducer.church(parse('(f)x')))
    assert_nil(Reducer.church(parse('3')))
  end

  def test_let
    assert_alpha_equal(church(4), normal_form('let two = &f.&x.(f)(f)x; ((+)two)two'))
    assert_equal('(&f.&x.(f)x)y', parse("let one = &f.&x.(f)x;\n(one)y\n").to_s)
    # bound occurrences are not replaced, and the definition is not captured
    assert_equal('&x.x', parse('let x = y; &x.x').to_s)
    assert_equal('&a.(y)a', parse('let x = y; &y.(x)y').to_s)
    # scoped like nested lets: later definitions see the earlier ones
    assert_equal('((y)y)z', parse('let a = y; let b = (a)a; (b)z').to_s)
    assert_equal('(x)y', parse('let a = x; let x = y; (a)x').to_s)
    assert_equal('a', parse('let b = a; let a = 3; b').to_s)
    # let is a keyword
    assert_equal('(lets)let_x', parse('(lets)let_x').to_s)
    assert_raise(Racc::ParseError) { parse('(let)x') }
    assert_raise(Racc::ParseError) { parse('let x = y x') }
    assert_raise(Racc::ParseError) { parse('let x = y;') }
    assert_raise(Racc::ParseError) { parse('x; let x = y; x') }
  end

  def test_steps
    nf, reducer = reduce('(&x.&y.x)y')
    assert_equal('&a.y', nf.to_s)
    assert_equal(4, reducer.steps)
    assert_equal(1, reducer.beta)
    assert_equal({ 'alpha' => 1, 'beta2' => 1, 'beta4' => 1, 'beta1' => 1 }, reducer.counts)
    assert_match(/\Asteps: 4 \(alpha 1, beta2 1, beta4 1, beta1 1\)  beta: 1  time: \d+\.\d{3}s\z/, reducer.stats)
    nf, reducer = reduce('(&x.&y.x)y', 'normal')
    assert_equal([1, 1, { 'beta' => 1 }], [reducer.steps, reducer.beta, reducer.counts])
    assert_match(/\Asteps: 1  beta: 1  time: \d+\.\d{3}s\z/, reducer.stats)
    nf, reducer = reduce('(&x.&y.x)y', 'need')
    assert_equal([1, 1, { 'beta' => 1 }], [reducer.steps, reducer.beta, reducer.counts])
    assert_kind_of(Float, reducer.time)
    # the beta count of revised is the number of steps of normal order;
    # need reduces the shared argument once
    src = '(&x.(x)x)(&y.y)z'
    assert_equal(3, reduce(src, 'revised')[1].beta)
    assert_equal(3, reduce(src, 'gc')[1].beta)
    assert_equal(3, reduce(src, 'normal')[1].beta)
    assert_equal(2, reduce(src, 'need')[1].beta)
    _, normal = reduce(PRELUDE + '(fact)four', 'normal')
    _, need = reduce(PRELUDE + '(fact)four', 'need')
    assert(need.beta < normal.beta / 2, "need #{need.beta} normal #{normal.beta}")
    assert_equal({ 'gc' => 1 }, reduce('(&x.(y)z)w', 'gc')[1].counts)
    assert_equal({ 'beta5' => 1, 'beta2' => 2 }, reduce('(&x.(y)z)w', 'revised')[1].counts)
  end

  def test_normal_steps
    steps = []
    reduce('(q)((&y.p)r)(&y.y)r', 'normal') {|*step| steps << step.map(&:to_s) }
    assert_equal([['beta', '(&y.p)r', 'p', '(q)(p)(&y.y)r'],
                  ['beta', '(&y.y)r', 'r', '(q)(p)r']], steps)
    steps = []
    reduce('(&x.&y.x)y', 'normal') {|*step| steps << step.map(&:to_s) }
    assert_equal([['beta', '(&x.&y.x)y', '&a.y', '&a.y']], steps)
    # the revised rules still report every step; gc after beta2 and beta3
    steps = []
    nf = reduce('(&x.&y.(x)(z)w)y', 'gc') {|*step| steps << step.map(&:to_s) }.first
    assert_equal('&a.(y)(z)w', nf.to_s)
    assert_equal(%w[alpha gc beta4 beta5 beta1 gc], steps.map(&:first))
  end

  # the strategies substitute independently (substitution vs. environments):
  # whenever two of them find normal forms they are the same, and a cycle is
  # never reported for a term that another strategy normalizes
  def test_random_terms
    random = Random.new(2024)
    vars = %w[x y z]
    gen = lambda {|depth|
      case (depth <= 0 ? 0 : random.rand(4))
      when 0 then vars[random.rand(vars.size)]
      when 1 then "&#{vars[random.rand(vars.size)]}.#{gen.call(depth - 1)}"
      else "(#{gen.call(depth - 1)})#{gen.call(depth - 1)}"
      end
    }
    found = 0
    300.times {
      src = gen.call(6)
      results = MODES.keys.map {|mode|
        begin
          [:nf, normal_form(src, mode, limit: 400).canonical]
        rescue Reducer::Cycle
          [:cycle]
        rescue Reducer::Limit
          [:limit]
        end
      }
      nfs = results.select {|r| r[0] == :nf }.map {|r| r[1] }.uniq
      assert(nfs.size <= 1, "#{src}: #{results.inspect}")
      assert(nfs.empty? || results.none? {|r| r[0] == :cycle }, "#{src}: #{results.inspect}")
      found += 1 unless nfs.empty?
    }
    assert(found > 200, "only #{found} normal forms")
  end

  # Church numerals of tens of thousands: printing, recognition, need and let
  # walk the right spine iteratively
  def test_deep_terms
    n = 10000
    node = parse(church(n))
    assert_equal(church(n), node.to_s)
    assert_equal(n.to_s, Reducer.church(node))
    assert_equal(Set[], node.free_vars)
    assert_equal(Set['f'], node.expr.free_vars)
    assert_equal(church(n), parse("let x = y; #{church(n)}").to_s)
    assert_alpha_equal(church(n + 1), normal_form("(\#{succ})#{church(n)}", 'need'))
    assert_alpha_equal(church(2 * n), normal_form("((+)#{church(n)})#{church(n)}", 'need'))
  end

  def test_cli_strategies
    input = '(&x.&y.x)y'
    expected = "\n---- reduce ----\n(&x.&y.x)y\n&a.y\n"
    assert_equal(expected, run_lambda('-s', 'normal', :input => input))
    assert_equal(expected, run_lambda('--strategy', 'need', :input => input))
    assert_equal("&a.y\n", run_lambda('-q', :input => input))
    assert_equal("&a.y\n", run_lambda('-s', 'need', '-q', :input => input))
    assert_equal("\n---- reduce ----\n(&x.&y.x)y\n  beta: (&x.&y.x)y -> &a.y\n&a.y\n",
                 run_lambda('-s', 'normal', '-v', :input => input))
    assert_equal(expected, run_lambda('-s', 'need', '-v', :input => input))
    out = run_lambda('-s', 'foo', :input => input)
    assert_equal(1, $?.exitstatus)
    assert_include(out, 'invalid argument: -s foo')
  end

  def test_cli_gc
    assert_equal("\n---- reduce ----\n(&x.(y)z)w\n  gc: (&x.(y)z)w -> (y)z\n(y)z\n",
                 run_lambda('-g', '-v', :input => '(&x.(y)z)w'))
    assert_equal("\n---- reduce ----\n(&x.(y)z)w\n((&x.y)w)(&x.z)w\n(y)(&x.z)w\n(y)z\n",
                 run_lambda(:input => '(&x.(y)z)w'))
  end

  def test_cli_church_and_stats
    assert_equal("&f.&x.(f)(f)(f)(f)(f)(f)x\n  = 6\n",
                 run_lambda('-q', '-c', :input => '((*)&f.&x.(f)(f)x)&f.&x.(f)(f)(f)x'))
    assert_equal("&x.&y.x\n  = true\n", run_lambda('-q', '--church', :input => '(#{zero})&f.&x.x'))
    assert_equal("&x.&y.y\n  = 0 (false)\n", run_lambda('-q', '-c', :input => '(#{zero})&f.&x.(f)x'))
    assert_equal("&x.x\n", run_lambda('-q', '-c', :input => '&x.x'))
    assert_equal("\n---- reduce ----\n(&x.x)&f.&x.(f)x\n&f.&x.(f)x\n  = 1\n", run_lambda('-c', :input => '(&x.x)&f.&x.(f)x'))
    assert_match(/\A&a\.y\n  steps: 4 \(alpha 1, beta2 1, beta4 1, beta1 1\)  beta: 1  time: \d+\.\d{3}s\n\z/,
                 run_lambda('-q', '--stats', :input => '(&x.&y.x)y'))
    assert_match(/\A\n---- reduce ----\n.*\n&f\.&x\.\(f\)\(f\)x\n  = 2\n  steps: \d+  beta: \d+  time: \d+\.\d{3}s\n\z/,
                 run_lambda('-s', 'need', '--stats', '-c', :input => '((+)&f.&x.(f)x)&f.&x.(f)x'))
  end

  def test_cli_no_normal_form
    out = run_lambda(:input => OMEGA)
    assert_equal(1, $?.exitstatus)
    assert_equal("\n---- reduce ----\n(&x.(x)x)&x.(x)x\n((&x.x)&x.(x)x)(&x.x)&x.(x)x\n(&x.(x)x)(&x.x)&x.(x)x\n" \
                 "(&x.(x)x)&x.(x)x\nno normal form: the term repeats itself (cycle detected at step 3)\n", out)
    out = run_lambda('-s', 'normal', :input => OMEGA)
    assert_equal(1, $?.exitstatus)
    assert_equal("\n---- reduce ----\n(&x.(x)x)&x.(x)x\n(&x.(x)x)&x.(x)x\n" \
                 "no normal form: the term repeats itself (cycle detected at step 1)\n", out)
    out = run_lambda('-s', 'need', '-l', '100', :input => OMEGA)
    assert_equal(1, $?.exitstatus)
    assert_equal("\n---- reduce ----\n(&x.(x)x)&x.(x)x\nno normal form within 100 steps (-l raises the limit, -l 0 removes it)\n", out)
    out = run_lambda('-q', '--limit', '3', '--stats', :input => '(&f.(&x.(f)(x)x)&x.(f)(x)x)g')
    assert_equal(1, $?.exitstatus)
    assert_match(/\Ano normal form within 3 steps \(-l raises the limit, -l 0 removes it\)\n  steps: 3 \(beta5 2, beta4 1\)  beta: 1  time: /, out)
    out = run_lambda('-s', 'normal', '-l', '0', :input => "(&x.y)#{OMEGA}")
    assert_equal(0, $?.exitstatus)
    assert_equal("\n---- reduce ----\n(&x.y)(&x.(x)x)&x.(x)x\ny\n", out)
  end

  def test_cli_eta
    assert_equal("\n---- reduce ----\n&x.&y.((f)x)y\n&x.(f)x\nf\n", run_lambda('-e', :input => '&x.&y.((f)x)y'))
    assert_equal("f\n", run_lambda('--eta', '-q', '-s', 'need', :input => '&x.&y.((f)x)y'))
    assert_include(run_lambda('-e', '-v', '-s', 'normal', :input => '&x.&y.((f)x)y'), "\n  eta: &y.((f)x)y -> (f)x\n&x.(f)x\n")
  end

  def test_cli_let
    Tempfile.create('lambda') {|f|
      f.write(PRELUDE + "(fact)three\n")
      f.close
      assert_equal("&f.&x.(f)(f)(f)(f)(f)(f)x\n  = 6\n", run_lambda('-s', 'need', '-q', '-c', f.path))
      assert_equal("&f.&x.(f)(f)(f)(f)(f)(f)x\n  = 6\n", run_lambda('-s', 'normal', '-q', '-c', f.path))
      assert_equal("&f.&x.(f)(f)(f)(f)(f)(f)x\n  = 6\n", run_lambda('-g', '-q', '-c', f.path))
    }
    assert_equal("&x.(y)x\n", run_lambda('-q', :input => "let one = &f.&x.(f)x;\n(one)y\n"))
    assert_equal("\n---- reduce ----\n(&f.&x.(f)x)y\n&x.(&f.(f)x)y\n&x.((&f.f)y)(&f.x)y\n&x.(y)(&f.x)y\n&x.(y)x\n",
                 run_lambda(:input => "let one = &f.&x.(f)x;\n(one)y\n"))
    assert_include(run_lambda(:input => 'let x = y x'), 'parse error')
  end

  # lambda.rb restarts itself with a large VM stack, so even the recursive
  # strategies handle deep terms
  def test_cli_deep_terms
    n = 20000
    assert_equal("#{church(n + 1)}\n  = #{n + 1}\n", run_lambda('-s', 'need', '-q', '-c', :input => "(\#{succ})#{church(n)}"))
    n = 10000
    assert_equal("#{church(n + 1)}\n  = #{n + 1}\n", run_lambda('-s', 'normal', '-q', '-c', :input => "(\#{succ})#{church(n)}"))
    n = 3000
    assert_equal("#{church(n + 1)}\n  = #{n + 1}\n", run_lambda('-q', '-c', :input => "(\#{succ})#{church(n)}"))
    # with the default 1MB stack (no restart), the recursive revised rules overflow
    out = IO.popen({ 'RUBY_THREAD_VM_STACK_SIZE' => '1048576' }, [RbConfig.ruby, LAMBDA_RB, '-q'], 'r+', :err => [:child, :out]) {|io|
      io.write("(\#{succ})#{church(10000)}")
      io.close_write
      io.read
    }
    assert_equal(1, $?.exitstatus)
    assert_equal("stack overflow: the term is too deep (try -s need, or a larger RUBY_THREAD_VM_STACK_SIZE)\n", out)
  end
end
