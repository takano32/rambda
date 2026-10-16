# rambda

## これ、何よ

Rubyで記述した型なしラムダ計算を行う簡約機です。

ラムダ式を読み込み、後述の revised alpha/beta 規則を 1 ステップずつ適用して、
正規形に至るまでの各ステップを表示します。

これに加えて、代入を一度に行う古典的な最左最外簡約 (`-s normal`) と、
引数を共有して必要なときに 1 度だけ評価する strong call-by-need (`-s need`) を選べます。
どの戦略も正規化的 (正規形があれば必ずそれに到達する) で、
正規形がない項は循環の検出とステップ数の上限で止まります。

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

正規形に到達すると終了ステータスは 0、正規形が見つからなかったときは 1 です。

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

### 簡約戦略の選択 (-s, --strategy)

| 戦略 | 1 ステップ | 表示 | 向いている用途 |
| --- | --- | --- | --- |
| `revised` (既定) | revised alpha/beta 規則 1 回 | 全ステップ | 代入の様子を 1 規則ずつ追う |
| `normal` | 最左最外の β 簡約 1 回 (代入は一度に) | 全ステップ | β 簡約の列を追う |
| `need` | (内部で) 共有付きの β 簡約 1 回 | 最初と正規形だけ | 大きな計算を速く終える |

`normal` は古典的な最左最外 (normal order) 簡約です。
代入 `E[x:=Q]` は捕獲を避けて一度に行い、束縛変数の改名は表示しません。

    $ echo '((*)&f.&x.(f)(f)x)&f.&x.(f)(f)(f)x' | ruby lambda.rb -s normal -v

    ---- reduce ----
    ((&m.&n.&f.(m)(n)f)&f.&x.(f)(f)x)&f.&x.(f)(f)(f)x
      beta: (&m.&n.&f.(m)(n)f)&f.&x.(f)(f)x -> &n.&f.(&f.&x.(f)(f)x)(n)f
    (&n.&f.(&f.&x.(f)(f)x)(n)f)&f.&x.(f)(f)(f)x
      beta: (&n.&f.(&f.&x.(f)(f)x)(n)f)&f.&x.(f)(f)(f)x -> &f.(&f.&x.(f)(f)x)(&f.&x.(f)(f)(f)x)f
    &f.(&f.&x.(f)(f)x)(&f.&x.(f)(f)(f)x)f
      beta: (&f.&x.(f)(f)x)(&f.&x.(f)(f)(f)x)f -> &x.((&f.&x.(f)(f)(f)x)f)((&f.&x.(f)(f)(f)x)f)x
    &f.&x.((&f.&x.(f)(f)(f)x)f)((&f.&x.(f)(f)(f)x)f)x
      beta: (&f.&x.(f)(f)(f)x)f -> &x.(f)(f)(f)x
    &f.&x.(&x.(f)(f)(f)x)((&f.&x.(f)(f)(f)x)f)x
      beta: (&x.(f)(f)(f)x)((&f.&x.(f)(f)(f)x)f)x -> (f)(f)(f)((&f.&x.(f)(f)(f)x)f)x
    &f.&x.(f)(f)(f)((&f.&x.(f)(f)(f)x)f)x
      beta: (&f.&x.(f)(f)(f)x)f -> &x.(f)(f)(f)x
    &f.&x.(f)(f)(f)(&x.(f)(f)(f)x)x
      beta: (&x.(f)(f)(f)x)x -> (f)(f)(f)x
    &f.&x.(f)(f)(f)(f)(f)(f)x

`need` は strong call-by-need です。引数は thunk として共有され、
最初に必要になったときに 1 度だけ評価されます
(上の例で `(&f.&x.(f)(f)(f)x)f` が 2 回簡約されているところが 1 回になります)。
途中の項は作らないので、最初の項と正規形だけを表示します。

    $ echo '((*)&f.&x.(f)(f)x)&f.&x.(f)(f)(f)x' | ruby lambda.rb -s need -c --stats

    ---- reduce ----
    ((&m.&n.&f.(m)(n)f)&f.&x.(f)(f)x)&f.&x.(f)(f)(f)x
    &f.&x.(f)(f)(f)(f)(f)(f)x
      = 6
      steps: 6  beta: 6  time: 0.000s

### ガベージコレクション規則 (-g, --gc)

既定の `revised` 戦略に、x が E に自由に出現しないときに `(&x.E)Q` を一歩で `E` にする
規則 `gc` を加えます (beta2, beta3 を一般化したもので、明示的代入の計算系 λxgc の gc 規則)。
beta5 で Q を E の隅々まで複製してから捨てる手間が省けるので、
ステップ数が数分の一になります (後述のベンチマーク参照)。
適用順は beta1, beta2, beta3, gc, beta4, beta5, alpha で、
beta2, beta3 が適用できる簡約基の表示は変わりません。

    $ echo '(&x.(y)z)w' | ruby lambda.rb -g -v

    ---- reduce ----
    (&x.(y)z)w
      gc: (&x.(y)z)w -> (y)z
    (y)z

### 正規形がないとき: 循環の検出とステップ数の上限 (-l, --limit)

`revised` と `normal` では、β 簡約のたびに項を de Bruijn 表現に直して
以前の項と比べ (Brent の循環検出法、メモリは O(1))、
項が α 同値の範囲で繰り返したら「正規形なし」として止まります。
Ω = `(&x.(x)x)&x.(x)x` はこれで止まります。

    $ ruby lambda.rb examples/omega.lambda

    ---- reduce ----
    (&x.(x)x)&x.(x)x
    ((&x.x)&x.(x)x)(&x.x)&x.(x)x
    (&x.(x)x)(&x.x)&x.(x)x
    (&x.(x)x)&x.(x)x
    no normal form: the term repeats itself (cycle detected at step 3)

    $ ruby lambda.rb -s normal examples/omega.lambda

    ---- reduce ----
    (&x.(x)x)&x.(x)x
    (&x.(x)x)&x.(x)x
    no normal form: the term repeats itself (cycle detected at step 1)

項が繰り返さずに大きくなり続ける場合 (`(Y)f` など) と、途中の項を持たない `need` では、
ステップ数の上限 (既定 1000000) で止まります。
`-l N` で上限を変え、`-l 0` で上限をなくせます。

    $ ruby lambda.rb -s need -l 1000 examples/omega.lambda

    ---- reduce ----
    (&x.(x)x)&x.(x)x
    no normal form within 1000 steps (-l raises the limit, -l 0 removes it)

どの戦略も最左最外の簡約基から簡約するので、正規形のない部分項が使われなければ
正規形に到達します。

    $ echo '(&x.y)(&x.(x)x)&x.(x)x' | ruby lambda.rb -q
    y

### η 簡約 (-e, --eta)

β 正規形に到達したあと、x が E に自由に出現しない `&x.(E)x` を `E` に簡約します
(η 簡約は β 簡約のあとに回せるので、β 正規形の η 正規形が βη 正規形です)。

    $ echo '&x.&y.((f)x)y' | ruby lambda.rb -e -v

    ---- reduce ----
    &x.&y.((f)x)y
      eta: &y.((f)x)y -> (f)x
    &x.(f)x
      eta: &x.(f)x -> f
    f

### チャーチ数・真偽値の表示 (-c, --church)

正規形がチャーチ数 `&f.&x.(f)...(f)x` か真偽値 `&x.&y.x`, `&x.&y.y` なら、
その値を続けて表示します (0 と false は同じ項です)。

    $ echo '(#{zero})&f.&x.x' | ruby lambda.rb -q -c
    &x.&y.x
      = true
    $ echo '(#{zero})&f.&x.(f)x' | ruby lambda.rb -q -c
    &x.&y.y
      = 0 (false)

### 正規形だけを表示 (-q, --quiet)、統計 (--stats)

`-q` は `---- reduce ----` も途中の項も表示せず、正規形だけを表示します。
`--stats` は最後にステップ数 (`revised` では規則ごとの内訳も)、
β 簡約の回数、所要時間を表示します。

    $ echo '(&x.&y.x)y' | ruby lambda.rb --stats

    ---- reduce ----
    (&x.&y.x)y
    (&x.&a.(&y.x)a)y
    (&x.&a.x)y
    &a.(&x.x)y
    &a.y
      steps: 4 (alpha 1, beta2 1, beta4 1, beta1 1)  beta: 1  time: 0.000s

    $ ruby lambda.rb -s need -q -c --stats examples/fact.lambda
    &f.&x.(f)(f)(f)...(f)x
      = 120
      steps: 1164  beta: 1164  time: 0.007s

### 深い項

数万のチャーチ数のような深い項では再帰が深くなるので、
`lambda.rb` は起動時に VM スタックを 256MB にした Ruby で自分自身を実行し直します
(環境変数 `RUBY_THREAD_VM_STACK_SIZE` が設定済みならそのまま使います。
メモリは実際に使った分しか消費しません)。
項の表示、チャーチ数の判定、自由変数の計算、`need` の読み戻しは
右側の連鎖を再帰なしでたどり、構文解析も項の深さに対して線形なので、
`-s need` なら 10 万のチャーチ数の succ も数秒で終わります。
それでもスタックが足りないときはメッセージを出して終了します。

### デバッグモード (-d, --debug)

racc の構文解析トレースを標準エラー出力に表示します。

    $ echo '(&x.x)y' | ruby lambda.rb -d
    read    "("("(") "("

    shift   "("
            [ ("(" "(") ]
    ...

### オプション一覧

    $ ruby lambda.rb -h
    Usage: lambda.rb [options] [file]
        -s, --strategy NAME              reduction strategy: revised, normal, need (default: revised)
        -g, --gc                         revised: add the rule gc (&x.E)Q -> E for x not free in E
        -l, --limit N                    give up after N steps (default: 1000000, 0: no limit)
        -e, --eta                        eta-reduce the normal form: &x.(E)x -> E for x not free in E
        -c, --church                     annotate the normal form when it is a Church numeral or boolean
        -q, --quiet                      print only the normal form
            --stats                      print the number of steps and the time taken
        -v, --verbose                    show the rule and the redex of each step
        -d, --debug                      show the racc parser trace

## 構文

    <program> ::= <definition>* <lambda-expression>
    <definition> ::= let <variable> = <lambda-expression> ;
    <lambda-expression> ::= <variable> | <constant> | <application> | <abstraction>
    <application> ::= (<lambda-expression>)<lambda-expression>
    <abstraction> ::= &<variable>.<lambda-expression>
    <builtin> ::= #{<name>} | #{<number>}

| 種類 | 書き方 | 例 |
| --- | --- | --- |
| 変数 | 英字または `_` で始まる英数字と `_` の列 (`let` を除く) | `x`, `E1`, `foo_bar` |
| 定数 | 数値リテラル。簡約されない定数として扱われる (`(&x.3)y` は `3` になる) | `3` |
| 適用 | `(E1)E2`。`(f)(g)x` は `f` を `(g)x` に適用する | `(f)x` |
| 抽象 | `&x.E` または `\x.E` | `&x.(f)x`, `\x.x` |

空白と改行は無視されます。

### 定義 (let)

`let 名前 = 式;` で式に名前を付けられます。
名前は、それ以降の定義と最後の式に自由に出現する箇所に置き換えられます
(束縛変数は置き換えず、置き換えで変数が捕獲されることもありません)。
後の定義ほど先に置き換えるので、入れ子の let と同じスコープになります。

    $ printf 'let two = &f.&x.(f)(f)x;\n((+)two)two\n' | ruby lambda.rb -s need -c

    ---- reduce ----
    ((&m.&n.&f.&x.((m)f)((n)f)x)&f.&x.(f)(f)x)&f.&x.(f)(f)x
    &f.&x.(f)(f)(f)(f)x
      = 4

### 組み込み

`#{名前}` と書くと、チャーチ符号化されたラムダ式に展開されます。
`#{0}`, `#{1}`, `#{2}`, ... はチャーチ数です。
展開の中で使っている組み込みも、その場で展開されます。
未定義の名前を書くと `parse error: unknown built-in #{名前}` になります。

#### コンビネータ

| 記法 | 展開 | 備考 |
| --- | --- | --- |
| `#{I}` | `&x.x` | 恒等関数 |
| `#{K}` | `&x.&y.x` | |
| `#{S}` | `&x.&y.&z.((x)z)(y)z` | |
| `#{B}` | `&x.&y.&z.(x)(y)z` | 関数合成 |
| `#{C}` | `&x.&y.&z.((x)z)y` | 引数の入れ替え |
| `#{W}` | `&x.&y.((x)y)y` | 引数の複製 |
| `#{omega}` | `&x.(x)x` | |
| `#{Omega}` | `(#{omega})#{omega}` | 正規形を持たない (循環を検出して停止) |
| `#{Y}` | `&f.(&x.(f)(x)x)&x.(f)(x)x` | 不動点コンビネータ (正規順序向け) |
| `#{Z}` | `&f.(&x.(f)&v.((x)x)v)&x.(f)&v.((x)x)v` | η 展開した不動点コンビネータ |

#### 真偽値

| 記法 | 展開 |
| --- | --- |
| `#{true}` | `&x.&y.x` |
| `#{false}` | `&x.&y.y` |
| `#{if}` | `&p.&a.&b.((p)a)b` |
| `#{not}` | `&p.((p)#{false})#{true}` |
| `#{and}` | `&p.&q.((p)q)p` |
| `#{or}` | `&p.&q.((p)p)q` |
| `#{xor}` | `&p.&q.((p)(#{not})q)q` |

#### 数

| 記法 | 展開 | 意味 |
| --- | --- | --- |
| `#{0}`, `#{1}`, ... | `&f.&x.x`, `&f.&x.(f)x`, ... | チャーチ数 |
| `#{succ}` | `&n.&f.&x.(f)((n)f)x` | n + 1 |
| `#{pred}` | `&n.(((n)&p.&z.((z)(#{succ})(p)#{true})(p)#{true})&z.((z)#{0})#{0})#{false}` | n - 1 (0 の pred は 0) |
| `#{plus}`, `+` | `&m.&n.&f.&x.((m)f)((n)f)x` | m + n |
| `#{mult}`, `*` | `&m.&n.&f.(m)(n)f` | m × n |
| `#{exp}` | `&m.&n.(n)m` | m の n 乗 |
| `#{sub}` | `&m.&n.((n)#{pred})m` | m - n (負になるときは 0) |
| `#{zero}`, `#{iszero}` | `&n.((n)(#{true})#{false})#{true}` | n = 0 |
| `#{leq}` | `&m.&n.(#{zero})((#{sub})m)n` | m ≤ n |
| `#{lt}` | `&m.&n.(#{not})((#{leq})n)m` | m < n |
| `#{eq}` | `&m.&n.((#{and})((#{leq})m)n)((#{leq})n)m` | m = n |

#### 組とリスト

リストは組で表します (nil = 組 (true, true)、cons h t = 組 (false, 組 (h, t)))。

| 記法 | 展開 |
| --- | --- |
| `#{pair}` | `&a.&b.&z.((z)a)b` |
| `#{fst}` | `&p.(p)#{true}` |
| `#{snd}` | `&p.(p)#{false}` |
| `#{nil}` | `&z.((z)#{true})#{true}` |
| `#{cons}` | `&h.&t.&z.((z)#{false})&w.((w)h)t` |
| `#{null}` | `#{fst}` (空リストか) |
| `#{head}` | `&l.(#{fst})(#{snd})l` |
| `#{tail}` | `&l.(#{snd})(#{snd})l` |

例 (`ruby lambda.rb -s need -q -c` の出力):

| 入力 | 正規形 |
| --- | --- |
| `((+)&f.&x.(f)x)&f.&x.(f)x` (1 + 1) | `&f.&x.(f)(f)x` (2) |
| `(#{pred})&f.&x.(f)(f)x` (pred 2) | `&f.&x.(f)x` (1) |
| `(#{zero})&f.&x.x` (zero? 0) | `&x.&y.x` (true) |
| `((#{exp})#{2})#{3}` (2^3) | `&x.&a.(x)(x)(x)(x)(x)(x)(x)(x)a` (8) |
| `((#{sub})#{5})#{2}` (5 - 2) | `&f.&x.(f)(f)(f)x` (3) |
| `((#{eq})#{3})#{3}` (3 = 3) | `&x.&y.x` (true) |
| `(#{head})(#{tail})((#{cons})#{1})((#{cons})#{2})#{nil}` | `&f.&x.(f)(f)x` (2) |
| `((#{Y})&g.&n.(((#{zero})n)#{1})((*)n)(g)(#{pred})n)#{4}` (4!) | 24 |

## メモ

### the revised alpha-rule

- alpha &x.E -> &z.(&x.E)z for any z /= phi(E)

### the revised beta-rules

- beta1 (&x.x)Q -> Q
- beta2 (&x.y)Q -> y
- beta3 (&x.&x.E)Q -> &x.E
- beta4 (&x.&y.E)Q -> &y.(&x.E)Q
- beta5 (&x.(E1)E2)Q -> ((&x.E1)Q)(&x.E2)Q

`-g` で加わる規則:

- gc (&x.E)Q -> E if x is not free in E

### 簡約戦略 (revised)

- 最左最外 (leftmost-outermost) の簡約基から順に簡約します。
- beta2 は y が定数の場合にも適用します。
- beta4 が適用できない (&x.&y.E)Q、つまり x が E に自由に出現し、
  かつ y が Q に自由に出現する場合は、内側の &y.E に alpha を適用します。
  新しい変数 z には E, Q, x, y に現れない名前を a, b, ..., z, a1, b1, ... の順に選びます。
- alpha で生じた (&y.E)z、beta4 で生じた (&x.E)Q、beta5 で生じた (&x.E1)Q と (&x.E2)Q は、
  他の簡約基より優先して簡約します (代入を完了させてから次に進みます)。

### 正規化性 (どの戦略も正規形があればそれに到達する)

- revised: 簡約は「最左最外の簡約基 (&x.E)Q を選ぶ」「その代入を beta1〜beta5 (と alpha) で
  完了させる」の繰り返しです。代入は E の大きさに関する帰納法で有限ステップで終わり、
  終わった時点の項は古典的な β 簡約の結果 E[x:=Q] と α 同値です
  (Révész の改訂規則は古典的な β 変換と同じ変換関係を定めます)。
  alpha で始まる区間は改名だけなので項は α 同値のままです。
  したがって代入の完了時点の項の列は、古典的なラムダ計算の最左最外簡約列そのものであり、
  標準化定理 (Curry–Feys 1958) の系として、項が正規形を持てば最左最外簡約はそれに到達します
  (Barendregt 1984, 定理 13.2.2)。
- normal: 上の最左最外簡約列を代入を一度に行って作るので、同じ議論が成り立ちます。
  代入 `substitute` は、Q に自由な束縛変数 y を Q, E, x に現れない名前に改名してから
  代入するので変数を捕獲しません。
- need: 引数は thunk として環境に入り、関数部分に現れて必要になったとき
  (または読み戻しで正規形の一部として必要になったとき) に 1 度だけ弱頭正規形まで評価され、
  その結果が共有されます。抽象の下へは、閉包を新しい変数に適用して読み戻すことで進みます。
  簡約される簡約基は normal order が簡約するものと同じで、共有された分だけ回数が減るので、
  normal order が正規形に到達する項では need も到達します。
  この strong call-by-need 戦略の β 正規形に対する完全性は
  Balabonski–Barenbaum–Bonelli–Kesner (ICFP 2017) が証明しており、
  本実装は lazy Krivine machine を strong reduction に拡張した RKNL
  (Biernacka–Charatonik–Drab, ICFP 2022) と同じ方針です
  (環境は連結リスト、変数を引数にする適用は thunk を共有、thunk の値は memo 化)。
  環境方式なので代入は行わず、読み戻しのときに束縛変数の名前が閉包の自由変数を
  捕獲しそうな場合だけ改名します。
- η: βη 正規形は β 正規形の η 正規形と一致します (η 後置性、Barendregt 1984, 15.1.6)。

### 循環の検出

`revised` と `normal` は、β 簡約で得た項の列を de Bruijn 表現 (`&f.&x.(f)x` は `&.&.(#1)#0`)
にして比べます。比較には Brent の循環検出法を使うので、保存するのは 1 つの項だけで、
周期 p の循環が m 番目の項から始まるなら 2(m + p) 程度の項を調べるまでに検出します。
項の表現を作るコストは項の大きさに比例するので、最初の 64 回の β 簡約では毎回、
その後は 64 回に 1 回だけ調べます (一定間隔で間引いた列も最終的に周期的なので、
循環は必ず見つかります)。
`need` には途中の項がないのでステップ数の上限だけで止めます。

### 採用しなかったもの

- Lamping の最適簡約 (optimal reduction): β 簡約の回数は最小になりますが、
  その帳簿付けのコストが指数的になりうることが知られており (Lawall–Mairson 1996)、
  実用上は共有付きの call-by-need のほうが速く、実装もはるかに単純です。
- 中間項の表示付きグラフ簡約: 共有された項を 1 行の項として表示すると共有が消えて
  大きさが元に戻るので、`need` では途中の項を表示しません。
- `need` での循環検出: 評価中の機械の状態を比べる必要があり、判定もできないので
  ステップ数の上限に任せています。

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

### examples/

Y コンビネータによる階乗とフィボナッチ数、べき乗、Ω の入力例です。

    $ cat examples/fact.lambda
    let Y = &f.(&x.(f)(x)x)&x.(f)(x)x;
    let one = &f.&x.(f)x;
    let five = &f.&x.(f)(f)(f)(f)(f)x;
    let fact = (Y)&g.&n.(((#{zero})n)one)((*)n)(g)(#{pred})n;
    (fact)five

    $ ruby lambda.rb -s need -q -c --stats examples/fact.lambda
    &f.&x.(f)(f)(f)...(f)x
      = 120
      steps: 1164  beta: 1164  time: 0.007s

    $ ruby lambda.rb -s need -q -c --stats examples/fib.lambda
    &f.&x.(f)(f)(f)...(f)x
      = 55
      steps: 11845  beta: 11845  time: 0.070s

## ベンチマーク

`rake bench` (`ruby bench.rb [1 セルあたりの秒数]`) で、チャーチ数の計算を各戦略で行い、
ステップ数と所要時間を Markdown の表にします。
`revised` の列は規則の適用回数で、括弧内は β 簡約の回数 (= `normal` のステップ数) です。
`need` のステップ数は共有付きの β 簡約の回数です。
(Ruby 3.3.8, 1 セル 60 秒まで)

| | revised | revised -g | normal | need |
| --- | ---: | ---: | ---: | ---: |
| succ 0 | 12 (3) / 0.000s | 11 (3) / 0.000s | 3 / 0.000s | 3 / 0.000s |
| 2 + 3 | 55 (6) / 0.003s | 43 (6) / 0.001s | 6 / 0.000s | 6 / 0.000s |
| 3 * 4 | 86 (9) / 0.001s | 76 (9) / 0.001s | 9 / 0.000s | 7 / 0.000s |
| 2 ^ 5 | 886 (62) / 0.032s | 534 (62) / 0.024s | 62 / 0.005s | 36 / 0.000s |
| 2 ^ 10 | 33339 (2114) / 21.264s | 18172 (2114) / 14.143s | 2114 / 0.940s | 1039 / 0.004s |
| pred 10 | 2814 (79) / 0.115s | 479 (79) / 0.033s | 79 / 0.017s | 79 / 0.002s |
| fact 3 | 27294 (1055) / 1.859s | 5409 (1055) / 0.463s | 1055 / 0.076s | 141 / 0.000s |
| fact 4 | 225926 (7122) / 18.183s | 37759 (7122) / 4.485s | 7122 / 0.338s | 331 / 0.001s |
| fact 5 | > 60s | > 60s | 53939 / 4.702s | 1164 / 0.002s |
| fib 5 | 96288 (2343) / 8.605s | 13166 (2343) / 2.499s | 2343 / 0.166s | 874 / 0.001s |
| fib 10 | > 60s | > 60s | 104422 / 10.999s | 11845 / 0.027s |

`revised` の列はこの変更前の簡約機と同じ動作 (規則の適用順も同じ) なので、変更前の数値でもあります。

`revised` は 1 ステップごとに項全体を走査するので、項が大きくなる計算では
ステップ数と項の大きさの積に時間がかかります。
`-g` で捨てられる部分項の複製をなくすとステップ数が数分の一になり、
`normal` は代入を一度に行うのでさらに少なく、
`need` は共有によって β 簡約の回数そのものが減ります (fact 4 で 7122 回が 331 回)。

## テスト

    $ rake test

または、パーサを生成した上で直接実行します。

    $ rake parser
    $ ruby test_beta2.rb     # revised 規則
    $ ruby test_reducer.rb   # 各戦略、循環検出、η、let、コマンドラインオプション

## 参考文献

- G. E. Révész, "Axioms for the theory of lambda-conversion", SIAM Journal on Computing 14(2), pp. 373–382, 1985.
  <https://epubs.siam.org/doi/10.1137/0214028> (代入を使わない改訂 α/β 規則)
- G. E. Révész, "Rule-based semantics for an extended lambda-calculus", MFPS 1987, LNCS 298.
  <https://link.springer.com/chapter/10.1007/3-540-19020-1_3>
- G. E. Révész, *Lambda-Calculus, Combinators, and Functional Programming*, Cambridge Tracts in Theoretical Computer Science 4, 1988.
- H. P. Barendregt, *The Lambda Calculus: Its Syntax and Semantics*, North-Holland, 1984.
  定理 13.2.2 (最左最外簡約の正規化性)、系 15.1.6 (η 後置性)
- Wikipedia, "Reduction strategy" (normal order は正規化的)
  <https://en.wikipedia.org/wiki/Reduction_strategy>
- T. Balabonski, P. Barenbaum, E. Bonelli, D. Kesner, "Foundations of strong call-by-need", PACMPL 1 (ICFP), 2017.
  <https://www.irif.fr/~kesner/papers/strong-call-by-need.pdf> (strong call-by-need の β 正規形に対する完全性)
- M. Biernacka, W. Charatonik, "Deriving an abstract machine for strong call by need", FSCD 2019.
  <https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.FSCD.2019.8>
- M. Biernacka, W. Charatonik, T. Drab, "A simple and efficient implementation of strong call by need by an abstract machine", ICFP 2022 / JFP 2026.
  <https://arxiv.org/abs/2102.05985> (RKNL: memothunk による lazy Krivine machine の strong reduction への拡張、normal order を bilinear に模倣)
- T. Balabonski, A. Lanco, G. Melquiond, "A strong call-by-need calculus", LMCS 19(1), 2023.
  <https://arxiv.org/abs/2111.01485>
- R. Bloo, K. H. Rose, "Preservation of strong normalisation in named lambda calculi with explicit substitution and garbage collection", CSN 1995 (λxgc の gc 規則).
  K. H. Rose, R. Bloo, F. Lang, "On explicit substitution with names", Journal of Automated Reasoning 49, 2012.
  <https://link.springer.com/article/10.1007/s10817-011-9222-5>
- Wikipedia, "Cycle detection" (Brent のアルゴリズム)
  <https://en.wikipedia.org/wiki/Cycle_detection>
- J. L. Lawall, H. G. Mairson, "Optimality and inefficiency: what isn't a cost model of the lambda calculus?", ICFP 1996.
  (最適簡約の帳簿付けコスト)
