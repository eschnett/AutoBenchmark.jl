using AutoBenchmark
using Base.Test

f(x::Float64) = 3.0*x+2.0
x0 = 0.0
@benchmark "muladd" f x0

@benchmark "sin" sin 1.0
