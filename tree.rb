require 'set'

# Lambda Expression Tree
class LambdaExpressionNode
  # mark: nil, true (pending redex: reduce before anything else)
  # or the name of the rule chosen by mark_first_redex
  attr_accessor :mark

  def initialize
    @mark = nil
  end

  # mark the redex to reduce next: a pending one if any (:pending),
  # otherwise the leftmost-outermost redex (true); false in normal form
  def mark_first_redex
    return :pending if marked?
    return mark_redex
  end

  def mark_redex
    return false
  end

  def marked?
    return false
  end

  # returns [node, rule, redex, result] or nil when nothing was reduced
  def reduce
    return nil
  end

  def beta(i)
    method = self.method("beta#{i}".intern)
    return method.call
  end

  # free variables
  def variables(binding = [])
    return []
  end

  # all variables, bound or free
  def all_variables
    return []
  end

  def copy
    return self
  end

  # names of the free variables as a Set; cached, so only for terms that are
  # not mutated afterwards (the revised rules mutate the tree and use #variables).
  # The right spine is walked iteratively, like to_s.
  attr_accessor :free_vars_cache

  def free_vars
    return @free_vars_cache if @free_vars_cache
    spine = []
    node = self
    while node.instance_of?(ApplicationNode) or node.instance_of?(AbstractionNode) do
      break if node.free_vars_cache
      spine.push(node)
      node = node.instance_of?(ApplicationNode) ? node.expr2 : node.expr
    end
    vars = spine.empty? ? Set.new : node.free_vars
    while (node = spine.pop) do
      if node.instance_of?(ApplicationNode) then
        vars = node.expr1.free_vars | vars
      else
        vars = vars - [node.var.to_s]
      end
      node.free_vars_cache = vars
    end
    return @free_vars_cache = vars
  end

  # E[x:=Q], capture-avoiding, building a new term (Q is shared, not copied)
  def substitute(name, term)
    return self
  end

  # one leftmost-outermost beta step (normal order), building a new term:
  # [term, redex, result] or nil in normal form
  def normal_step
    return nil
  end

  # one leftmost-outermost eta step &x.(E)x -> E (x not free in E):
  # [term, redex, result] or nil when there is none
  def eta_step
    return nil
  end

  # the term with bound variables as de Bruijn indices, &.&.(#1)#0 for
  # &f.&x.(f)x: two terms are alpha-equivalent iff their canonical forms are equal
  def canonical(env = [])
    s = +''
    node = self
    bound = 0
    loop do
      case node
      when ApplicationNode
        s << '(' << node.expr1.canonical(env) << ')'
        node = node.expr2
      when AbstractionNode
        env.push(node.var.to_s)
        bound += 1
        s << '&.'
        node = node.expr
      when VariableNode
        i = env.rindex(node.to_s)
        s << (i ? "##{env.size - 1 - i}" : node.to_s)
        break
      else
        s << node.to_s
        break
      end
    end
    env.pop(bound)
    return s
  end

  # (E1)E2 and &x.E; the right spine is printed iteratively so that long
  # application chains such as Church numerals do not overflow the stack
  def to_s
    s = +''
    node = self
    loop do
      case node
      when ApplicationNode
        s << '(' << node.expr1.to_s << ')'
        node = node.expr2
      when AbstractionNode
        s << '&' << node.var.to_s << '.'
        node = node.expr
      else
        return s << node.to_s
      end
    end
  end
end



class VariableNode < LambdaExpressionNode
  def initialize(var)
    super()
    @var = var
  end

  def variables(binding = [])
    if binding.include?(self) then
      return []
    else
      return [self]
    end
  end

  def all_variables
    return [self]
  end

  def copy
    return VariableNode.new(@var)
  end

  def free_vars
    @free_vars_cache ||= Set[@var]
  end

  def substitute(name, term)
    return @var == name ? term : self
  end

  # a, b, ..., z, a1, b1, ..., z1, a2, ... that is not in avoid (names)
  def self.fresh_name(avoid)
    i = 0
    loop do
      for z in 'a'..'z' do
        name = i == 0 ? z : "#{z}#{i}"
        return name unless avoid.include?(name)
      end
      i += 1
    end
  end

  def ==(target)
    return false unless target.instance_of?(VariableNode)
    return self.to_s == target.to_s
  end

  def eql?(target)
    return self == target
  end

  def hash
    return @var.hash
  end

  def to_s
    return @var
  end
end

class ConstantNode < LambdaExpressionNode
  attr_accessor :num
  def initialize(num)
    super()
    @num = num
  end

  def variables(binding = [])
    return []
  end

  def copy
    return ConstantNode.new(@num)
  end

  def ==(target)
    return false unless target.instance_of?(ConstantNode)
    return self.num == target.num
  end

  def eql?(target)
    return self == target
  end

  def hash
    return @num.hash
  end

  def to_s
    return @num.to_s
  end
end

class ApplicationNode < LambdaExpressionNode
  attr_accessor :expr1, :expr2
  def initialize(expr1, expr2)
    super()
    @expr1 = expr1
    @expr2 = expr2
  end

  RULES = %w[beta1 beta2 beta3 beta4 beta5 alpha]
  # with the garbage collection rule of lambda-x-gc (Bloo and Rose 1995):
  # (&x.E)Q -> E when x is not free in E, where beta2 and beta3 do not apply
  RULES_GC = %w[beta1 beta2 beta3 gc beta4 beta5 alpha]

  # the rules in use, in order of preference (set by Reducer)
  @rules = RULES
  class << self
    attr_accessor :rules
  end

  # name of the rule applicable to this node, or nil
  def rule
    for name in self.class.rules do
      return name if self.send("#{name}?")
    end
    return nil
  end

  def mark_redex
    @mark = rule
    return true if @mark
    return @expr1.mark_redex || @expr2.mark_redex
  end

  def marked?
    return true if @mark
    return @expr1.marked? || @expr2.marked?
  end

  def reduce
    if @mark then
      @mark = nil
      name = rule
      if name == 'alpha' then
        redex = @expr1.expr
        alpha
        return self, name, redex, @expr1.expr
      elsif name then
        node = self.send(name)
        return node, name, self, node
      end
    end

    node, *step = @expr1.reduce
    if node then
      @expr1 = node
      return self, *step
    end

    node, *step = @expr2.reduce
    if node then
      @expr2 = node
      return self, *step
    end
    return nil
  end

  def variables(binding = [])
    first_vars = @expr1.variables(binding)
    second_vars = @expr2.variables(binding)
    return first_vars + second_vars
  end

  def all_variables
    return @expr1.all_variables + @expr2.all_variables
  end

  def copy
    return ApplicationNode.new(@expr1.copy, @expr2.copy)
  end

  def substitute(name, term)
    return self unless free_vars.include?(name)
    return ApplicationNode.new(@expr1.substitute(name, term), @expr2.substitute(name, term))
  end

  def normal_step
    if @expr1.instance_of?(AbstractionNode) then
      result = @expr1.expr.substitute(@expr1.var.to_s, @expr2)
      return result, self, result
    end
    node, *step = @expr1.normal_step
    return ApplicationNode.new(node, @expr2), *step if node
    node, *step = @expr2.normal_step
    return ApplicationNode.new(@expr1, node), *step if node
    return nil
  end

  def eta_step
    node, *step = @expr1.eta_step
    return ApplicationNode.new(node, @expr2), *step if node
    node, *step = @expr2.eta_step
    return ApplicationNode.new(@expr1, node), *step if node
    return nil
  end


  # test alpha: (&x.&y.E)Q where beta4 is blocked,
  # i.e. x is free in E and y is free in Q
  def alpha?
    if @expr1.instance_of?(AbstractionNode) and
        @expr1.expr.instance_of?(AbstractionNode) and
        @expr1.var != @expr1.expr.var and
        @expr1.expr.expr.variables.include?(@expr1.var) and
        @expr2.variables.include?(@expr1.expr.var)  then
      return true
    end
    return false
  end

  # (&x.&y.E)Q -> (&x.&z.(&y.E)z)Q, z fresh for E, Q, x and y
  def alpha
    return nil unless alpha?
    used = @expr2.all_variables + [@expr1.var]
    @expr1.expr = @expr1.expr.alpha(used)
    return self
  end


  def beta1?
    if @expr1.instance_of?(AbstractionNode) and
        @expr1.expr.instance_of?(VariableNode) and
        @expr1.var == @expr1.expr then
      return true
    end
    return false
  end

  def beta1
    return nil unless beta1?
    return @expr2
  end

  def beta2?
    if @expr1.instance_of?(AbstractionNode) and
        ( @expr1.expr.instance_of?(ConstantNode) or
          ( @expr1.expr.instance_of?(VariableNode) and
            @expr1.var != @expr1.expr ) ) then
      return true
    end
    return false
  end

  def beta2
    return nil unless beta2?
    return @expr1.expr
  end

  def beta3?
    if @expr1.instance_of?(AbstractionNode) and
        @expr1.expr.instance_of?(AbstractionNode) and
        @expr1.var == @expr1.expr.var then
      return true
    end
    return false
  end

  def beta3
    return nil unless beta3?
    return AbstractionNode.new(@expr1.var, @expr1.expr.expr)
  end

  # (&x.E)Q -> E when x is not free in E (only with RULES_GC)
  def gc?
    if @expr1.instance_of?(AbstractionNode) and
        not @expr1.expr.variables.include?(@expr1.var) then
      return true
    end
    return false
  end

  def gc
    return nil unless gc?
    return @expr1.expr
  end

  def beta4?
    if @expr1.instance_of?(AbstractionNode) and
        @expr1.expr.instance_of?(AbstractionNode) and
        @expr1.var != @expr1.expr.var and
        ( not @expr1.expr.expr.variables.include?(@expr1.var) or
            not @expr2.variables.include?(@expr1.expr.var) ) then
      return true
    end
    return false
  end

  def beta4
    return nil unless beta4?
    x = AbstractionNode.new(@expr1.var, @expr1.expr.expr)
    q = ApplicationNode.new(x, @expr2)
    q.mark = true
    return AbstractionNode.new(@expr1.expr.var, q)
  end

  def beta5?
    if @expr1.instance_of?(AbstractionNode) and
        @expr1.expr.instance_of?(ApplicationNode) then
      return true
    end
    return false
  end

  def beta5
    return nil unless beta5?
    e1 = AbstractionNode.new(@expr1.var, @expr1.expr.expr1)
    e2 = AbstractionNode.new(@expr1.var, @expr1.expr.expr2)
    ee1 = ApplicationNode.new(e1, @expr2)
    ee2 = ApplicationNode.new(e2, @expr2.copy)
    ee1.mark = true
    ee2.mark = true
    return ApplicationNode.new(ee1, ee2)
  end
end

class AbstractionNode < LambdaExpressionNode
  attr_accessor :var, :expr
  def initialize(var, expr)
    super()
    @var = var
    @expr = expr
  end

  def mark_redex
    return @expr.mark_redex
  end

  def marked?
    return @expr.marked?
  end

  def reduce
    node, *step = @expr.reduce
    if node then
      @expr = node
      return self, *step
    end
    return nil
  end

  def variables(binding = [])
    return @expr.variables(binding + [@var])
  end

  def all_variables
    return [@var] + @expr.all_variables
  end

  def copy
    return AbstractionNode.new(@var.copy, @expr.copy)
  end

  # (&y.E)[x:=Q]: &y.E[x:=Q], after renaming y when it is free in Q
  def substitute(name, term)
    return self unless free_vars.include?(name)
    var = @var
    body = @expr
    if term.free_vars.include?(var.to_s) then
      var = VariableNode.new(VariableNode.fresh_name(term.free_vars | body.free_vars | [name]))
      body = body.substitute(@var.to_s, var)
    end
    return AbstractionNode.new(var, body.substitute(name, term))
  end

  def normal_step
    node, *step = @expr.normal_step
    return AbstractionNode.new(@var, node), *step if node
    return nil
  end

  def eta_step
    if @expr.instance_of?(ApplicationNode) and @expr.expr2 == @var and
        not @expr.expr1.free_vars.include?(@var.to_s) then
      return @expr.expr1, self, @expr.expr1
    end
    node, *step = @expr.eta_step
    return AbstractionNode.new(@var, node), *step if node
    return nil
  end

  # &y.E -> &z.(&y.E)z for a z not used in E, Q, ...
  def alpha(used = [])
    var = fresh_variable(used + all_variables)
    app = ApplicationNode.new(self, var)
    app.mark = true
    return AbstractionNode.new(var, app)
  end

  # a, b, ..., z, a1, b1, ..., z1, a2, ...
  def fresh_variable(used)
    return VariableNode.new(VariableNode.fresh_name(used.map(&:to_s)))
  end
end
