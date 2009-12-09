# Lambda Expression Tree
class LambdaExpressionNode
  # todo: implements variables method
  def initialize
    @mark = false
  end
    
  def mark_first_redex(canonical = false)
    return false
  end

  def reduce(e = [], q = [])
    return nil
  end

  def beta(i)
    method = self.method("beta#{i}".intern)
    return method.call
  end
  
  def variables(binding = [])
    return []
  end
end



class VariableNode < LambdaExpressionNode
  def initialize(var)
    @var = var
  end

  def variables(binding = [])
    if binding.include?(self) then
      return []
    else
      return [self]
    end
  end  

  def ==(target)
    return false unless target.instance_of?(VariableNode)
    return self.to_s == target.to_s
  end

  def to_s
    return @var
  end
end

class ConstantNode < LambdaExpressionNode
  attr_accessor :num
  def initialize(num)
    @num = num
  end

  def variables(binding = [])
    return []
  end

  def ==(target)
    self.num == target.num
  end

  def to_s
    return @num.to_s
  end
end

class ApplicationNode < LambdaExpressionNode
  attr_accessor :expr1, :expr2, :mark
  def initialize(expr1, expr2)
    @expr1 = expr1
    @expr2 = expr2
  end
  
  def mark_first_redex(canonical = false)
    for i in 1..5 do
      method = self.method("beta#{i}?".intern)
      @mark = "beta#{i}" if method.call
      return true if @mark
    end


    return true if (alpha? and alpha)
    
    mark1 = @expr1.mark_first_redex(canonical)
    return true if mark1
    mark2 = @expr2.mark_first_redex(canonical)
    return true if mark2
    return false
  end

  def reduce(e = [], q = [])
    if @mark then
      return beta1 if beta1?
      return beta2 if beta2?
      return beta3 if beta3?
      return beta4, true if beta4?
      return beta5 if beta5?
    end

    if @expr1.instance_of?(AbstractionNode) and
        @expr1.expr.instance_of?(AbstractionNode) then
      e << @expr1.expr.expr.variables
      q << @expr2.variables
    end

    
    node, marked = @expr1.reduce(e, q)
    if node then
      @expr1 = node
      return self, marked
    end
    
    node, marked = @expr2.reduce(e, q)
    if node then
      @expr2 = node
      return self, marked
    end
    return self
  end

  def variables(binding = [])
    first_vars = @expr1.variables(binding)
    second_vars = @expr2.variables(binding)
    return first_vars + second_vars
  end


  # test alpha reduce(based on beta4?)
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

  # mark
  def alpha
    return nil unless alpha?
    @expr1.expr.mark = true
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
    return @expr2 if beta1?
  end
  
  def beta2?
    if @expr1.instance_of?(AbstractionNode) and
        @expr1.expr.instance_of?(VariableNode) and
        @expr1.var != @expr1.expr then
      return true
    end
    return false
  end

  def beta2
    return nil unless beta2?
    return @expr1.expr if beta2?
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
    ee2 = ApplicationNode.new(e2, @expr2)
    return ApplicationNode.new(ee1, ee2)
  end

  def to_s
    return "(#{@expr1.to_s})#{@expr2.to_s}"
  end
end

class AbstractionNode < LambdaExpressionNode
  attr_accessor :var, :expr, :mark
  def initialize(var, expr)
    @var = var
    @expr = expr
  end

  def mark_first_redex(canonical = false)
    return @expr.mark_first_redex(canonical)
  end

  def variables(binding = [])
    binding << @var
    return @var.variables(binding) + @expr.variables(binding)
  end

  # e and q are bindings
  def reduce(e = [], q = [])    
    if @mark then
      return alpha(e, q) if alpha?(e, q)
    end

    node, marked = @expr.reduce
    if node then
      @expr = node
      return self, marked
    end
    return self
  end

  def alpha?(e, q)
    var = nil
    for z in 'a'..'z' do
      var = VariableNode.new(z)
      break unless e.include?(var)
      break unless q.include?(var)
      var = nil
    end
    return true if var
  end

  def alpha(e, q)
    var = nil
    for z in 'a'..'z' do
      var = VariableNode.new(z)
      break unless e.include?(var)
      break unless q.include?(var)
      var = nil
    end
    raise "No More Free Variable" unless var
    app = ApplicationNode.new(AbstractionNode.new(@var, @expr), var)
    app.mark = true
    return AbstractionNode.new(var, app), true
  end


  def to_s
    return "&#{@var}.#{@expr}"
  end
end

