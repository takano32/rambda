# rambda

## これ、何よ

Rubyで記述した型なしラムダ計算を行う簡約機です。

ラムダ式を読み込み、後述の revised alpha/beta 規則を 1 ステップずつ適用して、
正規形に至るまでの各ステップを表示します。

## 必要なもの

- Ruby 2.0 以降 (Ruby 3.3 で動作確認)
- racc (パーサの生成に使用。Ruby 3.3 以降では bundled gem として同梱。
  なければ `gem install racc`)
- rake
- test-unit (テストの実行にのみ必要)

## ビルド

パーサ `lambda.tab.rb` は `lambda.y` から racc で生成します
(生成物なので git では管理していません)。

    $ rake parser

`rake` だけを実行すると、パーサを生成してからテストを実行します。
`lambda.tab.rb` がない状態で `lambda.rb` を実行すると、
`rake` を実行するよう促すメッセージを出して終了します。
生成したパーサは `rake clean` で削除できます。

## 使い方

標準入力からラムダ式を読み込み、簡約の各ステップを 1 行ずつ表示します。

    $ echo '(&x.&y.x)y' | ruby lambda.rb

    ---- reduce ----
    (&x.&y.x)y
    (&x.&a.(&y.x)a)y
    (&x.&a.x)y
    &a.(&x.x)y
    &a.y

ファイル名を引数に指定すると、そのファイルから読み込みます
(出力は標準入力の場合と同じです)。

    $ echo '(&x.&y.x)y' > expr.txt
    $ ruby lambda.rb expr.txt

### 簡約詳細表示モード (-v, --verbose)

各ステップで適用した規則と、簡約基 (redex) とその簡約結果を表示します。

    $ echo '(&x.&y.x)y' | ruby lambda.rb -v

    ---- reduce ----
    (&x.&y.x)y
      alpha: &y.x -> &a.(&y.x)a
    (&x.&a.(&y.x)a)y
      beta2: (&y.x)a -> x
    (&x.&a.x)y
      beta4: (&x.&a.x)y -> &a.(&x.x)y
    &a.(&x.x)y
      beta1: (&x.x)y -> y
    &a.y

### デバッグモード (-d, --debug)

racc の構文解析トレースを標準エラー出力に表示します。

    $ echo '(&x.x)y' | ruby lambda.rb -d
    read    "("("(") "("

    shift   "("
            [ ("(" "(") ]
    ...

`-h` でオプションの一覧を表示します。

## 構文

    <lambda-expression> ::= <variable> | <constant> | <application> | <abstraction>
    <application> ::= (<lambda-expression>)<lambda-expression>
    <abstraction> ::= &<variable>.<lambda-expression>

| 種類 | 書き方 | 例 |
| --- | --- | --- |
| 変数 | 英字または `_` で始まる英数字と `_` の列 | `x`, `E1`, `foo_bar` |
| 定数 | 数値リテラル。簡約されない定数として扱われる (`(&x.3)y` は `3` になる) | `3` |
| 適用 | `(E1)E2`。`(f)(g)x` は `f` を `(g)x` に適用する | `(f)x` |
| 抽象 | `&x.E` または `\x.E` | `&x.(f)x`, `\x.x` |

空白と改行は無視されます。

### 組み込み

以下の記法はチャーチ符号化されたラムダ式に展開されます。

| 記法 | 展開 |
| --- | --- |
| `#{true}` | `&x.&y.x` |
| `#{false}` | `&x.&y.y` |
| `#{succ}` | `&n.&f.&x.(f)((n)f)x` |
| `#{pred}` | `&n.(((n)&p.&z.((z)(#{succ})(p)#{true})(p)#{true})&z.((z)&f.&x.x)&f.&x.x)#{false}` |
| `#{zero}` | `&n.((n)(#{true})#{false})#{true}` |
| `+` | `&m.&n.&f.&x.((m)f)((n)f)x` |
| `*` | `&m.&n.&f.(m)(n)f` |

例:

| 入力 | 正規形 |
| --- | --- |
| `((+)&f.&x.(f)x)&f.&x.(f)x` (1 + 1) | `&f.&x.(f)(f)x` (2) |
| `(#{pred})&f.&x.(f)(f)x` (pred 2) | `&f.&x.(f)x` (1) |
| `(#{zero})&f.&x.x` (zero? 0) | `&x.&y.x` (true) |

## メモ

### the revised alpha-rule

- alpha &x.E -> &z.(&x.E)z for any z /= phi(E)

### the revised beta-rules

- beta1 (&x.x)Q -> Q
- beta2 (&x.y)Q -> y
- beta3 (&x.&x.E)Q -> &x.E
- beta4 (&x.&y.E)Q -> &y.(&x.E)Q
- beta5 (&x.(E1)E2)Q -> ((&x.E1)Q)(&x.E2)Q

### 簡約戦略

- 最左最外 (leftmost-outermost) の簡約基から順に簡約します。
- beta2 は y が定数の場合にも適用します。
- beta4 が適用できない (&x.&y.E)Q、つまり x が E に自由に出現し、
  かつ y が Q に自由に出現する場合は、内側の &y.E に alpha を適用します。
  新しい変数 z には E, Q, x, y に現れない名前を a, b, ..., z, a1, b1, ... の順に選びます。
- alpha で生じた (&y.E)z、beta4 で生じた (&x.E)Q、beta5 で生じた (&x.E1)Q と (&x.E2)Q は、
  他の簡約基より優先して簡約します (代入を完了させてから次に進みます)。

## 例

### succ

    &n.&f.&x.(f)((n)f)x

    $ echo '(#{succ})&f.&x.x' | ruby lambda.rb

    ---- reduce ----
    (&n.&f.&x.(f)((n)f)x)&f.&x.x
    &f.(&n.&x.(f)((n)f)x)&f.&x.x
    &f.&x.(&n.(f)((n)f)x)&f.&x.x
    &f.&x.((&n.f)&f.&x.x)(&n.((n)f)x)&f.&x.x
    &f.&x.(f)(&n.((n)f)x)&f.&x.x
    &f.&x.(f)((&n.(n)f)&f.&x.x)(&n.x)&f.&x.x
    &f.&x.(f)(((&n.n)&f.&x.x)(&n.f)&f.&x.x)(&n.x)&f.&x.x
    &f.&x.(f)((&f.&x.x)(&n.f)&f.&x.x)(&n.x)&f.&x.x
    &f.&x.(f)((&f.&x.x)f)(&n.x)&f.&x.x
    &f.&x.(f)((&f.&x.x)f)x
    &f.&x.(f)(&x.(&f.x)f)x
    &f.&x.(f)(&x.x)x
    &f.&x.(f)x

## テスト

    $ rake test

または、パーサを生成した上で直接実行します。

    $ rake parser
    $ ruby test_beta2.rb
