class BaseLambdaExpressionParser

# <program> ::= <definition>* <term>
# <definition> ::= let <variable> = <term> ;
# <term> ::= <application> | <application> <abstraction> | <abstraction>
# <abstraction> ::= λ <variable>+ . <term>   (λ or \; λx y. M is λx. λy. M)
# <application> ::= <atom> | <application> <atom>   (left associative)
# <atom> ::= <variable> | <constant> | ( <term> )
# <constant> ::= <number> | + | * | <builtin>
# <builtin> ::= #{<name>} | #{<number>}, see BUILTINS
#
# Every rule has at most three symbols: racc takes the values of a reduced
# rule as a slice of the LR stack, and Ruby shares the stack with a slice of
# four or more elements, so the next push copies the whole stack (quadratic
# in the depth of the nesting, i.e. in the size of a Church numeral).

rule

# a definition names a term for the free occurrences of the variable in the
# definitions after it and in the expression; later definitions are
# substituted first, so the names are scoped like nested lets
program : definitions term
    {
      result = val[1]
      @definitions.reverse_each {|name, term| result = result.substitute(name, term) }
    }

definitions :
    | definitions definition

definition : let_name term ';'
    {
      @definitions.push [val[0], val[1]]
    }

let_name : LET IDENT '='
    {
      result = val[1]
    }

# the body of an abstraction extends as far right as possible, so an
# abstraction can only be the last argument: f x λy. M is f x (λy. M)
term : application
    | application abstraction
    {
      result = ApplicationNode.new(val[0], val[1])
    }
    | abstraction

abstraction : binders '.' term
    {
      result = val[2]
      val[0].reverse_each {|var| result = AbstractionNode.new(var, result) }
    }

binders : LAMBDA variable
    {
      result = [val[1]]
    }
    | binders variable
    {
      result = val[0].push(val[1])
    }

application : atom
    | application atom
    {
      result = ApplicationNode.new(val[0], val[1])
    }

atom : variable
    | constant
    | '(' term ')'
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

end

---- header

require 'stringio'
require 'strscan'

---- inner
  # racc trace output; effective only when the parser was generated with racc -g
  attr_accessor :yydebug

  # f: an IO or StringIO; the input is UTF-8 (for λ) whatever the locale says
  def parse( f )
    @q = []
    @definitions = []
    f.each{|line|
      line = line.dup.force_encoding(Encoding::UTF_8)
      raise Racc::ParseError, 'invalid UTF-8 input' unless line.valid_encoding?
      s = StringScanner.new(line)
      until s.eos? do
        if s.skip(/\s+/)
        elsif s.scan(/λ|\\/)
          @q.push [:LAMBDA, s.matched]
        elsif s.scan(/#\{(\w+)\}/)
          @q.push [:BUILTIN, s[1]]
        elsif s.scan(/[a-zA-Z_][0-9a-zA-Z_]*'*/)
          @q.push [s.matched == 'let' ? :LET : :IDENT, s.matched]
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
    'I' => 'λx. x',
    'K' => 'λx y. x',
    'S' => 'λx y z. x z (y z)',
    'B' => 'λx y z. x (y z)',
    'C' => 'λx y z. x z y',
    'W' => 'λx y. x y y',
    'omega' => 'λx. x x',
    'Omega' => '#{omega} #{omega}',
    'Y' => 'λf. (λx. f (x x)) (λx. f (x x))',
    'Z' => 'λf. (λx. f (λv. x x v)) (λx. f (λv. x x v))',
    # booleans
    'true' => 'λx y. x',
    'false' => 'λx y. y',
    'if' => 'λp a b. p a b',
    'not' => 'λp. p #{false} #{true}',
    'and' => 'λp q. p q p',
    'or' => 'λp q. p p q',
    'xor' => 'λp q. p (#{not} q) q',
    # pairs: pair a b = λz. z a b
    'pair' => 'λa b z. z a b',
    'fst' => 'λp. p #{true}',
    'snd' => 'λp. p #{false}',
    # numerals: #{0}, #{1}, ... are the Church numerals
    'succ' => 'λn f x. f (n f x)',
    # pred n = snd (n (λp. pair (succ (fst p)) (fst p)) (pair 0 0))
    'pred' => 'λn. n (λp z. z (#{succ} (p #{true})) (p #{true})) (λz. z #{0} #{0}) #{false}',
    'plus' => 'λm n f x. m f (n f x)',
    'mult' => 'λm n f. m (n f)',
    'exp' => 'λm n. n m',
    'sub' => 'λm n. n #{pred} m',
    # zero n = n (λx. false) true, where true false = λy. false
    'zero' => 'λn. n (#{true} #{false}) #{true}',
    'leq' => 'λm n. #{zero} (#{sub} m n)',
    'eq' => 'λm n. #{and} (#{leq} m n) (#{leq} n m)',
    'lt' => 'λm n. #{not} (#{leq} n m)',
    # lists: nil = pair true true, cons h t = pair false (pair h t)
    'nil' => 'λz. z #{true} #{true}',
    'cons' => 'λh t z. z #{false} (λw. w h t)',
    'null' => '#{fst}',
    'head' => 'λl. #{fst} (#{snd} l)',
    'tail' => 'λl. #{snd} (#{snd} l)',
  }
  BUILTINS['iszero'] = BUILTINS['zero']

  # the Church numeral λf x. f (f ... (f x)) is built directly, not parsed
  def expand(name)
    if name =~ /\A\d+\z/ then
      body = VariableNode.new('x')
      name.to_i.times { body = ApplicationNode.new(VariableNode.new('f'), body) }
      return AbstractionNode.new(VariableNode.new('f'), AbstractionNode.new(VariableNode.new('x'), body))
    end
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
