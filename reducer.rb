require 'set'
require_relative 'tree'

# Reduces a term to its normal form with one of three normalizing strategies
# (each finds the normal form whenever the term has one):
#
# revised: the revised alpha/beta rules of tree.rb, one rule per step, on the
#   leftmost-outermost redex; the substitution started by a redex is finished
#   before the next redex is chosen, so every completed substitution is one
#   classical beta step of the leftmost-outermost redex.  The sequence of these
#   is a normal order reduction, which is normalizing by the standardization
#   theorem (Curry and Feys 1958; Barendregt 1984, Theorem 13.2.2).
# normal: normal order with the substitution done at once, one beta per step.
# need: strong call-by-need: arguments are shared and reduced at most once,
#   only when needed; complete for beta normal forms (Balabonski, Barenbaum,
#   Bonelli and Kesner, ICFP 2017).  No intermediate terms are produced.
#
# revised and normal compare the terms between beta steps up to alpha and
# report a cycle (as for Omega); every strategy stops at the step limit.
class Reducer
  STRATEGIES = %w[revised normal need]
  LIMIT = 1_000_000
  # the cycle check (canonical form, O(size)) runs at each of the first
  # CYCLE_CHECK beta steps and then every CYCLE_CHECK-th one: a fixed-stride
  # sample of an eventually periodic sequence is eventually periodic, so every
  # cycle is still found, and Omega-like loops are reported at once
  CYCLE_CHECK = 64

  class NoNormalForm < StandardError
    attr_reader :steps
    def initialize(message, steps)
      super(message)
      @steps = steps
    end
  end
  # the term came back to itself (up to alpha), so the reduction never ends
  class Cycle < NoNormalForm; end
  # the step limit was reached
  class Limit < NoNormalForm; end

  attr_reader :strategy, :steps, :beta, :counts, :time

  # beta: number of (classical) beta steps; steps and counts: the steps taken
  # per rule name (for need, the beta steps with sharing)
  def initialize(term, strategy: 'revised', limit: LIMIT, eta: false, gc: false)
    raise ArgumentError, "unknown strategy #{strategy}" unless STRATEGIES.include?(strategy.to_s)
    @term = term
    @strategy = strategy.to_s
    @limit = limit
    @eta = eta
    @gc = gc
    @steps = 0
    @beta = 0
    @counts = Hash.new(0)
    @time = nil
  end

  # returns the normal form, yielding [rule, redex, result, term] after each
  # step that produces a term (every step of revised and normal, eta steps);
  # raises Cycle or Limit when no normal form was found
  def run(&block)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      node = send("run_#{@strategy}", &block)
      node = run_eta(node, &block) if @eta
    ensure
      @time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end
    return node
  end

  # e.g. "steps: 12 (alpha 1, beta1 1, beta2 1, beta4 1)  beta: 2  time: 0.001s"
  def stats
    s = "steps: #{@steps}"
    s << " (#{@counts.map {|rule, n| "#{rule} #{n}" }.join(', ')})" unless @counts.empty? or @counts.keys == ['beta']
    s << "  beta: #{@beta}"
    s << "  time: #{'%.3f' % @time}s" if @time
    return s
  end

  # "3", "true", "false" or "0 (false)" when the term is a Church numeral
  # or boolean (0 and false are the same term), nil otherwise
  NUMERAL = /\A&\.&\.((?:\(#1\))*)#0\z/
  def self.church(term)
    c = term.canonical
    return 'true' if c == '&.&.#1'
    m = NUMERAL.match(c) or return nil
    n = m[1].size / 4
    return n == 0 ? '0 (false)' : n.to_s
  end

  private

  def run_revised
    node = @term
    cycle = CycleDetector.new
    rules = ApplicationNode.rules
    ApplicationNode.rules = @gc ? ApplicationNode::RULES_GC : ApplicationNode::RULES
    while (pending = node.mark_first_redex) do
      # no substitution in progress: the term is the result of whole beta steps
      canonical = node.canonical if pending != :pending and check_cycle?
      check_limit
      node, rule, redex, result = node.reduce
      # a macro step that starts with alpha only renames, and the term
      # stays alpha-equivalent: the cycle check sees the beta steps only
      if pending != :pending and rule != 'alpha' then
        raise Cycle.new(cycle_message, @steps) if canonical and cycle.repeat?(canonical)
        @beta += 1
      end
      canonical = nil
      step(rule)
      yield rule, redex, result, node if block_given?
    end
    return node
  ensure
    ApplicationNode.rules = rules if rules
  end

  def run_normal
    node = @term
    cycle = CycleDetector.new
    loop do
      raise Cycle.new(cycle_message, @steps) if check_cycle? and cycle.repeat?(node.canonical)
      result, redex, contractum = node.normal_step
      break unless result
      check_limit
      node = result
      step('beta')
      @beta += 1
      yield 'beta', redex, contractum, node if block_given?
    end
    return node
  end

  def run_need
    machine = Need.new(@limit)
    begin
      return machine.normalize(@term)
    ensure
      @steps = @beta = @counts['beta'] = machine.steps
    end
  end

  def run_eta(node)
    while (s = node.eta_step) do
      node, redex, result = s
      step('eta')
      yield 'eta', redex, result, node if block_given?
    end
    return node
  end

  def step(rule)
    @steps += 1
    @counts[rule] += 1
  end

  def check_limit
    raise Limit.new(Reducer.limit_message(@limit), @steps) if @limit > 0 and @steps >= @limit
  end

  def check_cycle?
    return @beta < CYCLE_CHECK || @beta % CYCLE_CHECK == 0
  end

  def cycle_message
    return "no normal form: the term repeats itself (cycle detected at step #{@steps})"
  end

  def self.limit_message(limit)
    return "no normal form within #{limit} step#{'s' unless limit == 1}"
  end

  # Brent's cycle detection on the canonical forms of the successive terms:
  # O(1) memory, and a repetition of period p that starts at term m is found
  # within about 2(m + p) terms (the tortoise is renewed at the powers of two)
  class CycleDetector
    def initialize
      @tortoise = nil
      @power = 1
      @count = 0
    end

    def repeat?(canonical)
      return true if canonical == @tortoise
      @count += 1
      if @count == @power then
        @tortoise = canonical
        @power *= 2
        @count = 0
      end
      return false
    end
  end

  # Strong call-by-need normalization: a closure-based evaluator with memoized
  # thunks (an argument is reduced at most once, and only when its value is
  # needed) whose weak head normal forms are read back into terms, going under
  # a binder by applying the closure to a fresh variable.  It is the lazy
  # Krivine machine extended to strong reduction (Biernacka, Charatonik and
  # Drab's RKNL, ICFP 2022): it contracts the redexes normal order contracts,
  # shared ones only once, so it normalizes exactly the terms that normal
  # order normalizes (Balabonski et al. 2017).  Evaluation recurses only along
  # the function part of applications; readback walks the right spine of a
  # neutral term iteratively.
  class Need
    Thunk = Struct.new(:term, :env, :value, :fv)
    Closure = Struct.new(:var, :body, :env, :fv)
    # a free variable or a constant applied to thunks
    Neutral = Struct.new(:head, :args)
    # an environment is nil or [name, thunk, environment]

    attr_reader :steps

    def initialize(limit)
      @limit = limit
      @steps = 0
      @scope = Hash.new(0)   # binders opened by readback, for choosing names
    end

    def normalize(term)
      @free = term.free_vars
      return readback(evaluate(term, nil))
    end

    private

    def lookup(env, name)
      while env do
        return env[1] if env[0] == name
        env = env[2]
      end
      return nil
    end

    # weak head normal form: a Closure or a Neutral
    def evaluate(term, env)
      loop do
        case term
        when ApplicationNode
          fun = evaluate(term.expr1, env)
          arg = term.expr2
          # an argument that is a variable shares the thunk it is bound to
          thunk = (arg.instance_of?(VariableNode) && lookup(env, arg.to_s)) || Thunk.new(arg, env)
          if fun.instance_of?(Closure) then
            beta_step
            term = fun.body
            env = [fun.var, thunk, fun.env]
          else
            return Neutral.new(fun.head, fun.args + [thunk])
          end
        when AbstractionNode
          return Closure.new(term.var.to_s, term.expr, env)
        when VariableNode
          thunk = lookup(env, term.to_s)
          return thunk ? force(thunk) : Neutral.new(term, [])
        else
          return Neutral.new(term, [])
        end
      end
    end

    def force(thunk)
      return thunk.value if thunk.value
      value = evaluate(thunk.term, thunk.env)
      thunk.value = value
      thunk.term = thunk.env = nil
      return value
    end

    def beta_step
      raise Limit.new(Reducer.limit_message(@limit), @steps) if @limit > 0 and @steps >= @limit
      @steps += 1
    end

    # the normal form of a weak head normal form
    def readback(value)
      spine = []   # binders and function parts passed on the way down the right spine
      result = nil
      loop do
        if value.instance_of?(Closure) then
          var = VariableNode.new(fresh(value))
          @scope[var.to_s] += 1
          spine.push [:abs, var]
          thunk = Thunk.new(nil, nil, Neutral.new(var, []))
          value = evaluate(value.body, [value.var, thunk, value.env])
        else
          args = value.args
          if args.empty? then
            result = value.head
            break
          end
          fun = value.head
          i = 0
          while i < args.size - 1 do
            fun = ApplicationNode.new(fun, readback(force(args[i])))
            i += 1
          end
          spine.push [:app, fun]
          value = force(args[-1])
        end
      end
      i = spine.size - 1
      while i >= 0 do
        kind, node = spine[i]
        if kind == :abs then
          @scope[node.to_s] -= 1
          result = AbstractionNode.new(node, result)
        else
          result = ApplicationNode.new(node, result)
        end
        i -= 1
      end
      return result
    end

    # the name for the binder of a closure: its own unless that would capture
    # a free variable of the closure (checked only when the name is in use)
    def fresh(closure)
      name = closure.var
      return name unless @scope[name] > 0 or @free.include?(name)
      fv = fv_closure(closure)
      return name unless fv.include?(name)
      avoid = fv.dup
      @scope.each {|n, count| avoid << n if count > 0 }
      return VariableNode.fresh_name(avoid)
    end

    # the free variables of a closure or thunk (an over-approximation: those
    # of its term, each looked up in its environment)
    def fv_closure(closure)
      closure.fv ||= fv_term(closure.body, closure.env, closure.var)
    end

    def fv_thunk(thunk)
      thunk.fv ||= (thunk.value ? fv_value(thunk.value) : fv_term(thunk.term, thunk.env, nil))
    end

    def fv_value(value)
      return fv_closure(value) if value.instance_of?(Closure)
      fv = Set.new
      fv << value.head.to_s if value.head.instance_of?(VariableNode)
      args = value.args
      i = 0
      while i < args.size do
        fv.merge(fv_thunk(args[i]))
        i += 1
      end
      return fv
    end

    def fv_term(term, env, bound)
      fv = Set.new
      names = term.free_vars.to_a
      i = 0
      while i < names.size do
        name = names[i]
        i += 1
        next if name == bound
        thunk = lookup(env, name)
        thunk ? fv.merge(fv_thunk(thunk)) : fv << name
      end
      return fv
    end
  end
end
