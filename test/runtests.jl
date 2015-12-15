using AutoBenchmark
using Base.Test

@benchmark "muladd" muladd 0.0 3.0 -2.0
@benchmark "muladd(lambda)" (x,a,b)->muladd(x,a,b) 0.0 3.0 -2.0
@benchmark "sin" sin 1.0
sum1(s,a) = s - sum(a)
@benchmark "sum" sum1 0.0 [1.0*i for i in 1:100]
