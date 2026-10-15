class BaseLambdaExpressionParser

# <program> ::= <definition>* <lambda-expression>
# <definition> ::= let <variable> = <lambda-expression> ;
# <lambda-expression> ::= <variable> | <constant> | <application> | <abstraction>
# <application> ::= (<lambda-expression>)<lambda-expression>
# <abstraction> ::= &<variable>.<lambda-expression>

rule

# a definition names a term for the free occurrences of the variable in the
# definitions after it and in the expression; later definitions are
# substituted first, so the names are scoped like nested lets
program : definitions lambda_expression
    {
      result = val[1]
      @definitions.reverse_each {|name, term| result = result.substitute(name, term) }
    }

definitions :
    | definitions definition

definition : LET IDENT '=' lambda_expression ';'
    {
      @definitions.push [val[1], val[3]]
    }

lambda_expression : atom
    | application

atom : variable
    | constant
    | abstraction

# (E1)(E2)...(En)E: the function parts are collected into a list, reduced
# after each ')', and folded from the right.  Parsing the chain as nested
# applications instead would push the whole chain on the LR stack, and each
# reduction copies a slice of that stack (quadratic in the length of the
# chain, i.e. in the size of a Church numeral).
application : functions atom
    {
      result = val[1]
      val[0].reverse_each {|f| result = ApplicationNode.new(f, result) }
    }

functions : function
    {
      result = [val[0]]
    }
    | functions function
    {
      result = val[0].push(val[1])
    }

function : '(' lambda_expression ')'
    {
      result = val[1]
    }

variable : IDENT
    {
		result = VariableNode.new(val[0])
    }

constant : number | operator | combinator

number : NUMBER
    {
      result = ConstantNode.new(val[0])
    }

operator : arithmetic_operator | predicate

arithmetic_operator : plus | mult | succ | pred

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

# pred n = snd (n (&p.pair (succ (fst p)) (fst p)) (pair 0 0))
#   pair a b = &z.((z)a)b, fst p = (p)true, snd p = (p)false, 0 = &f.&x.x
pred : PRED
    {
		result = parse_parse('&n.(((n)&p.&z.((z)(#{succ})(p)#{true})(p)#{true})&z.((z)&f.&x.x)&f.&x.x)#{false}')
    }

# zero n = (n (&x.false)) true, where (true)false = &y.false
predicate : ZERO
    {
		result = parse_parse('&n.((n)(#{true})#{false})#{true}')
    }

combinator : true | false

true : TRUE
    {
		result = parse_parse('&x.&y.x')
    }

false : FALSE
    {
		result = parse_parse('&x.&y.y')
    }

abstraction : lambda variable '.' lambda_expression
    {
		result = AbstractionNode.new(val[1], val[3])
    }

lambda : '&' | '\\'


end

---- header

require 'stringio'
require 'strscan'

---- inner
  # racc trace output; effective only when the parser was generated with racc -g
  attr_accessor :yydebug

  def parse( f )
    @q = []
    @definitions = []
    f.each{|line|
      s = StringScanner.new(line)
      until s.eos? do
        if s.skip(/\s+/)
        elsif s.scan(/let\b/)
          @q.push [:LET, s.matched]
        elsif s.scan(/#\{succ\}/)
          @q.push [:SUCC, s.matched]
        elsif s.scan(/#\{pred\}/)
          @q.push [:PRED, s.matched]
        elsif s.scan(/#\{zero\}/)
          @q.push [:ZERO, s.matched]
        elsif s.scan(/#\{true\}/)
          @q.push [:TRUE, s.matched]
        elsif s.scan(/#\{false\}/)
          @q.push [:FALSE, s.matched]
        elsif s.scan(/[a-zA-Z_][0-9a-zA-Z_]*/)
          @q.push [:IDENT, s.matched]
        elsif s.scan(/\d+/)
          @q.push [:NUMBER, s.matched.to_i]
        else
          c = s.getch
          @q.push [c, c]
        end
      end
    }
    @q.push [false, '$end']
    do_parse
  end

  def next_token
    @q.shift
  end

  def parse_parse(str)
    parser = self.class.new
    parser.yydebug = @yydebug
    sio = StringIO.new(str)
    return parser.parse(sio)
  end
