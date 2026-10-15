# Lambda Expression Tree
class LambdaExpressionNode
  # mark: nil, true (pending redex: reduce before anything else)
  # or the name of the rule chosen by mark_first_redex
  attr_accessor :mark

  def initialize
    @mark = nil
  end

  # mark the redex to reduce next: a pending one if any,
  # otherwise the leftmost-outermost redex
  def mark_first_redex
    return true if marked?
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

  # name of the rule applicable to this node, or nil
  def rule
    for name in RULES do
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

  def to_s
    return "(#{@expr1.to_s})#{@expr2.to_s}"
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

  # &y.E -> &z.(&y.E)z for a z not used in E, Q, ...
  def alpha(used = [])
    var = fresh_variable(used + all_variables)
    app = ApplicationNode.new(self, var)
    app.mark = true
    return AbstractionNode.new(var, app)
  end

  # a, b, ..., z, a1, b1, ..., z1, a2, ...
  def fresh_variable(used)
    i = 0
    loop do
      for z in 'a'..'z' do
        var = VariableNode.new(i == 0 ? z : "#{z}#{i}")
        return var unless used.include?(var)
      end
      i += 1
    end
  end


  def to_s
    return "&#{@var}.#{@expr}"
  end
end

