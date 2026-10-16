class BaseLambdaExpressionParser

# <program> ::= <definition>* <lambda-expression>
# <definition> ::= let <variable> = <lambda-expression> ;
# <lambda-expression> ::= <variable> | <constant> | <application> | <abstraction>
# <application> ::= (<lambda-expression>)<lambda-expression>
# <abstraction> ::= &<variable>.<lambda-expression>
# <builtin> ::= #{<name>} | #{<number>}, see BUILTINS

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

constant : number | operator | builtin

number : NUMBER
    {
      result = ConstantNode.new(val[0])
    }

operator : '+'
    {
      result = expand('plus')
    }
    | '*'
    {
      result = expand('mult')
    }

builtin : BUILTIN
    {
      result = expand(val[0])
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
        elsif s.scan(/#\{(\w+)\}/)
          @q.push [:BUILTIN, s[1]]
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

  # Church encodings; a definition may use the built-ins defined before it
  BUILTINS = {
    # combinators
    'I' => '&x.x',
    'K' => '&x.&y.x',
    'S' => '&x.&y.&z.((x)z)(y)z',
    'B' => '&x.&y.&z.(x)(y)z',
    'C' => '&x.&y.&z.((x)z)y',
    'W' => '&x.&y.((x)y)y',
    'omega' => '&x.(x)x',
    'Omega' => '(#{omega})#{omega}',
    'Y' => '&f.(&x.(f)(x)x)&x.(f)(x)x',
    'Z' => '&f.(&x.(f)&v.((x)x)v)&x.(f)&v.((x)x)v',
    # booleans
    'true' => '&x.&y.x',
    'false' => '&x.&y.y',
    'if' => '&p.&a.&b.((p)a)b',
    'not' => '&p.((p)#{false})#{true}',
    'and' => '&p.&q.((p)q)p',
    'or' => '&p.&q.((p)p)q',
    'xor' => '&p.&q.((p)(#{not})q)q',
    # pairs: pair a b = &z.((z)a)b
    'pair' => '&a.&b.&z.((z)a)b',
    'fst' => '&p.(p)#{true}',
    'snd' => '&p.(p)#{false}',
    # numerals: #{0}, #{1}, ... are the Church numerals
    'succ' => '&n.&f.&x.(f)((n)f)x',
    # pred n = snd (n (&p.pair (succ (fst p)) (fst p)) (pair 0 0))
    'pred' => '&n.(((n)&p.&z.((z)(#{succ})(p)#{true})(p)#{true})&z.((z)#{0})#{0})#{false}',
    'plus' => '&m.&n.&f.&x.((m)f)((n)f)x',
    'mult' => '&m.&n.&f.(m)(n)f',
    'exp' => '&m.&n.(n)m',
    'sub' => '&m.&n.((n)#{pred})m',
    # zero n = (n (&x.false)) true, where (true)false = &y.false
    'zero' => '&n.((n)(#{true})#{false})#{true}',
    'leq' => '&m.&n.(#{zero})((#{sub})m)n',
    'eq' => '&m.&n.((#{and})((#{leq})m)n)((#{leq})n)m',
    'lt' => '&m.&n.(#{not})((#{leq})n)m',
    # lists: nil = pair true true, cons h t = pair false (pair h t)
    'nil' => '&z.((z)#{true})#{true}',
    'cons' => '&h.&t.&z.((z)#{false})&w.((w)h)t',
    'null' => '#{fst}',
    'head' => '&l.(#{fst})(#{snd})l',
    'tail' => '&l.(#{snd})(#{snd})l',
  }
  BUILTINS['iszero'] = BUILTINS['zero']

  def expand(name)
    return parse_parse('&f.&x.' + '(f)' * name.to_i + 'x') if name =~ /\A\d+\z/
    src = BUILTINS[name]
    raise Racc::ParseError, "unknown built-in \#{#{name}}" unless src
    return parse_parse(src)
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
