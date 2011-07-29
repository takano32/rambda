class BaseLambdaExpressionParser

# <lambda-expression> ::= <variable> | <constant> | <application> | <abstraction>
# <application> ::= (<lambda-expression>)<lambda-expression>
# <abstraction> ::= &<variable>.<lambda-expression>

rule
lambda_expression : variable
    | constant
    | application
    | abstraction
    {
		result = val[0]
	 }
variable : IDENT
    {
		result = VariableNode.new(val[0])
	 }

constant : number | operator | combinator
    {
		result = val[0]
	 }
number : NUMBER
    {
      result = ConstantNode.new(val[0])
    }
operator : arithmetic_operator | predicate
    {
		result = val[0]
    }
arithmetic_operator : plus | mult | succ | pred
    {
		result = val[0]
    }
plus : '+'
    {
		result = parse_parse('&m.&n.&f.&x.((m)f)((n)f)x')
    }
mult : '*'
    {
		result = parse_parse('&m.&n.&f.(m)(n)f')
    }
succ : SUCC
    {
		result = parse_parse('&n.&f.&x.(f)((n)f)x')
    }
pred : PRED
    {
		zero = '&f.&x.x'
		result = parse_parse("&n.(((n)&p.&z.((z)(\#{succ})(p)\#{true})(p)\#{true})&z.((z)#{zero})#{zero})\#{false}")
    }
predicate : ZERO
    {
		result = parse_parse('&n.((n)(#{true})#{false})#{true}')
    }
combinator : true | false
    {
		 result = val[0]
	 }
true : TRUE
    {
		result = parse_parse('&x.&y.x')
    }
false : FALSE
    {
		result = parse_parse('&x.&y.y')
    }
application : '(' lambda_expression ')' lambda_expression
    {
		result = ApplicationNode.new(val[1], val[3])
    }
abstraction : '&' variable '.' lambda_expression
    {
		result = AbstractionNode.new(val[1], val[3])
	 }
end

---- header

require 'stringio'

---- inner
  def parse( f )
    @q = []
    f.each{|line|
      while line.size > 0 do
        case line
        when /\A\s+/o
        when /\A#\{succ\}/o
          @q.push [:SUCC, $&]
        when /\A#\{pred\}/o
          @q.push [:PRED, $&]
        when /\A#\{zero\}/o
          @q.push [:ZERO, $&]
        when /\A#\{true\}/o
          @q.push [:TRUE, $&]
        when /\A#\{false\}/o
          @q.push [:FALSE, $&]
        when /\A[a-zA-Z_][0-9a-zA-Z_]*/o
          @q.push [:IDENT, $&]
        when /\A\d+/o
          @q.push [:NUMBER, $&.to_i]
        when /\A.|\n/o
          @q.push [$&, $&]
        end
        line = $'
      end
    }
    @q.push [false, '$end']
    @yydebug = true
    do_parse
  end

  def next_token
    @q.shift
  end

  def parse_parse(str)
    parser = self.class.new
	 sio = StringIO.new(str)
	 return parser.parse(sio)    
  end
