# 記法について: 旧記法と標準記法への切り替え

## 経緯

rambda は 2007 年ごろに書かれ、2009 年 12 月に git へ取り込まれました (最初のコミットは 2009-12-09)。
当初の記法は、作者が読んだ Révész の教科書
*Lambda-Calculus, Combinators and Functional Programming* (1988) にならったもので、
適用を `(M)N` (関数側だけを括弧で囲む)、抽象を `&x.M` (ASCII の `&` を λ の代わりに使う。
のちに `\x.M` も可) と書いていました。簡約規則も同書・同著者の論文の改訂 α/β 規則です。

同じ `(t)u` の適用記法は Krivine の *Lambda-calculus, Types and Models* でも使われています
(第 1 章: "The term (t)u should be thought of as 't applied to u'; it will also be denoted by tu
if there is no ambiguity")。

2026-10-16 に、Barendregt、Hindley–Seldin、Pierce (TAPL) などの教科書で標準的な記法に
全面的に切り替えました。旧記法は受け付けず、切り替えるオプションもありません。

- 標準記法で書かれた教科書や論文の式を、そのまま入力し、出力と見比べられる。
- `(f)(g)x` は適用の向きが読み取りにくく、`((f)x)y` のように左結合の適用ほど括弧が増える。
- `λx y. M` のような標準的な略記を入れやすい。

## 旧記法

    <lambda-expression> ::= <variable> | <constant> | <application> | <abstraction>
    <application> ::= (<lambda-expression>)<lambda-expression>
    <abstraction> ::= &<variable>.<lambda-expression>

`(E1)E2` は E1 を E2 に適用した項で、括弧をつけるのは関数側だけです。
`(f)(g)x` は `(g)x` に `f` を適用した項 (標準記法の `f (g x)`)、
`((f)x)y` は `(f)x` に `y` を適用した項 (`f x y`) になります。
抽象の本体は右へできるだけ延び、`&x.(f)x` は `λx. f x` です。

## 標準記法 (現在)

抽象は `λx. M` または `\x. M` で、`λx y z. M` は `λx. λy. λz. M` の略記です。
適用は並置で左結合 (`f x y` は `(f x) y`)、抽象より強く結合し、括弧はグループ化のためだけに使います。
抽象の本体は右へできるだけ延びるので、引数の抽象は括弧で囲みます
(最後の引数のときだけ `f λx. x y` = `f (λx. x y)` のように省けます)。
変数名には `x'` のように `'` を続けられます。

出力は括弧を最小限にした同じ記法で、連続する抽象はまとめます (`λf x. f (f x)`)。
`--ascii` で `λ` の代わりに `\` を表示します。

## 対応表

| | 旧記法 | 標準記法 |
| --- | --- | --- |
| 抽象 | `&x.M`, `\x.M` | `λx. M`, `\x. M` |
| 入れ子の抽象 | `&x.&y.M` | `λx y. M` (`λx. λy. M` も可) |
| 適用 | `(M)N` | `M N` |
| 左結合の適用 (f x) y | `((f)x)y` | `f x y` |
| 右に入れ子の適用 f (g x) | `(f)(g)x` | `f (g x)` |
| 抽象の適用 Ω | `(&x.(x)x)&x.(x)x` | `(λx. x x) (λx. x x)` |
| チャーチ数 2 | `&f.&x.(f)(f)x` | `λf x. f (f x)` |
| succ | `&n.&f.&x.(f)((n)f)x` | `λn f x. f (n f x)` |
| beta4 | `(&x.&y.E)Q -> &y.(&x.E)Q` | `(λx. λy. E) Q -> λy. (λx. E) Q` |
| beta5 | `(&x.(E1)E2)Q -> ((&x.E1)Q)(&x.E2)Q` | `(λx. E1 E2) Q -> (λx. E1) Q ((λx. E2) Q)` |
| de Bruijn 表現 (内部) | `&.&.(#1)#0` | `λ.λ.#1 #0` |

## 付録: 参考文献

- György E. Révész, *Lambda-Calculus, Combinators and Functional Programming*,
  Cambridge Tracts in Theoretical Computer Science 4, Cambridge University Press, 1988, x+181 pp.,
  ISBN 0-521-34589-8. <https://ci.nii.ac.jp/ncid/BA03432683>
- G. E. Révész, "Axioms for the theory of lambda-conversion", *SIAM Journal on Computing* 14(2),
  pp. 373–382, 1985. <https://doi.org/10.1137/0214028> (改訂 α/β 規則)
- H. P. Barendregt, *The Lambda Calculus: Its Syntax and Semantics*,
  Studies in Logic and the Foundations of Mathematics 103, revised edition, North-Holland, 1984, xv+621 pp.,
  ISBN 0-444-87508-5. <https://ci.nii.ac.jp/ncid/BA01309096>
- J. Roger Hindley, Jonathan P. Seldin, *Lambda-Calculus and Combinators: An Introduction*,
  2nd edition, Cambridge University Press, 2008, ISBN 978-0-521-89885-0.
  <https://doi.org/10.1017/CBO9780511809835>
- Benjamin C. Pierce, *Types and Programming Languages*, The MIT Press, 2002, ISBN 0-262-16209-1.
  <https://www.cis.upenn.edu/~bcpierce/tapl/>
- Jean-Louis Krivine, *Lambda-calculus, Types and Models*, translated by René Cori, Ellis Horwood, 1993
  (原著 *Lambda-calcul, types et modèles*, Masson, 1990)。英訳の PDF が著者のページにあります。
  <https://www.irif.fr/~krivine/articles/Lambda.pdf>

### 作者が読んだ本

- György E. Révész, *Lambda-Calculus, Combinators and Functional Programming*,
  Cambridge Tracts in Theoretical Computer Science 4, Cambridge University Press, 1988, x+181 pp.,
  ISBN 0-521-34589-8 (2009 年にペーパーバックで再刊、ISBN 978-0-521-11429-5)。
  <https://ci.nii.ac.jp/ncid/BA03432683>
  - 2007 年ごろに書いた最初の rambda は、この本の (M)N 記法と改訂 β 規則、pred の導出をもとにしている。
