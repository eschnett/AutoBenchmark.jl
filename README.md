# AutoBenchmark

[![Build Status](https://travis-ci.org/eschnett/AutoBenchmark.jl.svg?branch=master)](https://travis-ci.org/eschnett/AutoBenchmark.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/aju6jyvfrm616ukk?svg=true)](https://ci.appveyor.com/project/eschnett/autobenchmark-jl)
[![codecov.io](https://codecov.io/github/eschnett/AutoBenchmark.jl/coverage.svg?branch=master)](https://codecov.io/github/eschnett/AutoBenchmark.jl?branch=master)
[![Dependency Status](https://dependencyci.com/github/eschnett/AutoBenchmark.jl/badge)](https://dependencyci.com/github/eschnett/AutoBenchmark.jl)

Run benchmarks, automatically fine-tuning the benchmark parameters.



## Basic Principle

Benchmarking is difficult. It is very easy to either include an
unrelated side-effect in a measurement, or to have a clever compiler
optimize away an important part of the benchmarked functionality, or
to be misled by timing noise. This package addresses these issues.

Note: There are other benchmarking packages available for Julia as
well. This package `AutoBenchmark` differs by its approach to ensuring
the compiler can't optimize away anything.

The basic principle for `AutoBenchmark` is: Only things that are
actually observed by the caller of a function can be guaranteed to not
be optimized away. Thus benchmarking a function that returns `Void` is
usually a bad idea (unless the function has some other side effect,
such as creating a file or communicating over the network). Thus all
benchmarked functions here need to return a value, and this value must
depend on "everything" that the function calculated.

Since many functions execute too quickly to be reliably timed, they
need to be executed multiple times. To ensure that the benchmarking
driver doesn't introduce overhead, this should happen in such a way
that the compiler can optimize the repeated executions, without being
able to optimize too much. For example, when executing a small
function `N` times, using loop unrolling would be fine, but executing
the function only `1` time and deducing the overall result from this
would not. Thus we demand that the function being benchmarked must
also accept a value as input, in such a way that multiple function
calls can be daisy-chained.

This works quite naturally in many cases. For example, benchmarking
the `sqrt` function looks like this:

```Julia
julia> using AutoBenchmark
julia> @benchmark "sqrt" sqrt 1.0;
Benchmarking sqrt:
.........................
Best result:
    npar=2 nseq=2 nloops=2097152 ntries=3
    min=2.039 ns   avg=2.103 ns   max=2.175 ns   total=0.018 s
```

This benchmarks the function `sqrt`, which accepts one value as input
and produces one value as output. We use the value `1.0` as starting
value. (The string `"sqrt"` is just a name we give to this benchmark.)

The benchmark driver will then generate code that looks approximately
like this:

```Julia
function runbench_seq{T}(x::T)
    for i in 1:nseq
        x = sqrt(x)
    end
    x
end
```

This will run the `sqrt` function `nseq` times, giving the compiler
the opportunity to heavily optimize this loop, but at the same time
preventing it from optimizing away any of the actual `sqrt` calls.

In fact, the actual benchmark code gives the compiler even more
opportunity to optimize. It allows the compiler to execute some of the
`sqrt` calls simultaneously:

```Julia
function runbench_par{T}(xs::NTuple{npar,T})
    for i in 1:nseq
        xs = map(sqrt, xs)
    end
    xs
end
```

This chooses `npar` (different) starting values `x`, and calls `sqrt`
simultaneously on each of them. Of course, the code is generated in
such a way to guarantee that `map` does not lead to an overhead. (The
implementation doesn't actually call `map`; both the `for` loop and
the `map` call are open-coded.)

Finally, the benchmark driver then tries various different
combinations of the values `nseq` and `npar` to find the optimum
combination. For each combination, it ensures that the benchmark runs
at least for 0.01 seconds. This optimization is repeated three times
(`ntries=3`). The best result is reported.

Here we found (this was run on an `Intel(R) Core(TM) i7-4980HQ CPU @
2.80GHz`):

```
Best result:
    npar=2 nseq=2 nloops=2097152 ntries=3
    min=2.039 ns   avg=2.103 ns   max=2.175 ns   total=0.018 s
```

This means: The best parameter combination was `npar=2` and `nseq=2`.
This benchmark function was called in a loop with `2097152` iterations
to ensure a sufficiently long run time, here at least 0.018 seconds.
This procedure was repeated `ntries=3` times.

The best run time was 2.039 nanoseconds per `sqrt` invokation. The
average and maximum run times were slightly larger, and give an
indication of the benchmarking noise.

Given a CPU frequency of 2.8 GHz, each `sqrt` invokation took about
5.7 cycles. This is the right order of magnitude if we compare this to
Intel's CPU documentation.

Since we allowed for parallel execution, this measured the throughput,
not the latency of a single `sqrt` call. To find the latency, we need
to consider the result for `npar=1`, which is reported as 2.540
nanoseconds (or about 7.1 cycles) per `sqrt` call, i.e. only slightly
more.



## Examples

All examples below were run on an `Intel(R) Core(TM) i7-4980HQ CPU @
2.80GHz`.



### Floating-point arithmetic:

Note that we are not using `@fastmath` here. This would likely give a
small speedup for the more complex operations (`sqrt`, `sin`), but we
would also need to be more careful to ensure that daisy-chained
function calls couldn't trivially be optimized away by the compiler.

#### Function `sqrt`:

```Julia
julia> @benchmark "sqrt" sqrt 1.0;
Benchmarking sqrt:
.........................
Best result:
    npar=4 nseq=4 nloops=524288 ntries=3
    min=2.051 ns   avg=2.310 ns   max=2.579 ns   total=0.019 s
```

#### Function `sin`:

```Julia
julia> @benchmark "sin" sin 1.0;
Benchmarking sin:
.........................
Best result:
    npar=8 nseq=8 nloops=32768 ntries=3
    min=4.821 ns   avg=4.920 ns   max=5.094 ns   total=0.010 s
```

`sqrt` is faster than `sin` since there is a special hardware
instruction for it on this CPU.

#### Floating-point addition:

```Julia
julia> @benchmark "fadd" (+) 1.0 2.0;
Benchmarking fadd:
.........................
Best result:
    npar=8 nseq=8 nloops=1048576 ntries=3
    min=0.252 ns   avg=0.253 ns   max=0.255 ns   total=0.017 s
```

With a CPU frequency of 2.8 GHz, this makes for about 0.7 cycles per
floating-point add (amortized). This CPU has a superscalar
architecture that can execute two floating-point instructions per
cycle, so we're not quite seeing the maximum theoretical performance.

#### Floating-point multiply-add:

```Julia
julia> @benchmark "fmuladd" muladd 1.0 2.0 3.0;
Benchmarking fmuladd:
.........................
Best result:
    npar=8 nseq=2 nloops=4194304 ntries=3
    min=0.268 ns   avg=0.292 ns   max=0.330 ns   total=0.020 s
```

This CPU has a fused multiply-add instruction, and also a hardware
unit that can multiply and add in one go. Thus `muladd` is as fast as
`+` for floating-point numbers.

#### Floating-point division:

```Julia
julia> @benchmark "fdiv" (/) 1.0 2.0;
Benchmarking fdiv:
.........................
Best result:
    npar=4 nseq=1 nloops=2097152 ntries=3
    min=2.022 ns   avg=2.153 ns   max=2.411 ns   total=0.018 s
```

Floating-point division is about ten times more more expensive than
addition and multiplication, it has the same cost as a square root.



### Integer arithmetic

The "problem" with integer arithmetic is that the compiler is much
more aggressive when optimizing it. We thus need to introduce helper
functions at a few occasions to ensure the compiler doesn't optimize
away our `nseq` loops.

#### Integer addition:

```Julia
julia> @benchmark "iadd" (+) 1 2;
Benchmarking add:

*** Could not obtain any results ***
Most likely, the benchmark kernel is too simple,
and the optimizer was able to collapse multiple chained invocations.
```

Okay, this didn't work. The problem is that, if the compiler sees a
sequence of `nseq` chained integer additions, it will fold these to a
single addition. We need to create a function that adds two numbers
where the compiler cannot do this.

A reversed subtraction (which is equivalent to an addition) does the
trick:

```Julia
julia> isub(x,y) = y-x
julia> @benchmark "isub" isub 1 2;
Benchmarking isub:
.....
Best result:
    npar=8 nseq=1 nloops=8388608 ntries=3
    min=0.225 ns   avg=0.230 ns   max=0.235 ns   total=0.015 s
```

So an integer addition (or subtraction) takes the same time as a
floating-point addition. That is to be expected on this CPU.

#### Integer multiplication:

```Julia
julia> @benchmark "imul" (*) 1 2;
Benchmarking imul:
.........................
Best result:
    npar=16 nseq=16 nloops=4194304 ntries=3
    min=0.016 ns   avg=0.016 ns   max=0.016 ns   total=0.017 s
```

In this case, `AutoBenchmark` didn't complain, but the result is
highly suspicious as well. The ideal parameter combination is reported
as consisting of `npar=16` and `nseq=16`, i.e. 256 operations. The
time per operation is more than ten times faster than an addition,
corresponding to 22 multiplications per cycle. This is clearly bogus
-- the compiler was able to optimize a chain of multiplications to a
single multiplications. Similar to the `isub` case above, we need to
use a more complex function.

Here we choose combined multiply-add function. Since we already know
how long an addition takes, we can try to deduce the cost of a
multiplication. This is only an indirect measurement, but is probably
the best we can do here.

```Julia
julia> @benchmark "imuladd" muladd 1 2 3;
Benchmarking imuladd:
.........................
Best result:
    npar=4 nseq=8 nloops=2097152 ntries=3
    min=0.252 ns   avg=0.253 ns   max=0.255 ns   total=0.017 s
```

This is only slightly longer than an integer addition. Apparently, the
multiplications and additions can be executed (at least partly) in
parallel. We thus cannot deduce the cost of an integer multiplication.

#### Integer division:

julia> @benchmark "idiv" div 1 2;
Benchmarking idiv:
.........................
Best result:
    npar=4 nseq=16 nloops=32768 ntries=3
    min=6.415 ns   avg=6.449 ns   max=6.472 ns   total=0.014 s
```
