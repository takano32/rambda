======
rambda
======

これ、何よ
----------

Rubyで記述した型なしラムダ計算を行う簡約機です。

メモ
----

the revised alpha-rule
^^^^^^^^^^^^^^^^^^^^^^

- alpha &x.E -> &z.(&x.E)z for any z /= phi(E)

the revised beta-rules
^^^^^^^^^^^^^^^^^^^^^^

- beta1 (&x.x)Q -> Q
- beta2 (&x.y)Q -> y
- beta3 (&x.&y.E)Q -> &x.E
- beta4 (&x.&y.E)Q -> &y.(&x.E)Q
- beta5 (&x.(E1)E2)Q -> ((&x.E1)Q)(&x.E2)Q

例
--

succ
^^^^

::

&n.&f.&x.(f)((n)f)x


ToDo
----
簡約詳細表示モードの実装


