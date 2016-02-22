module AutoBenchmark

export @benchmark
export Config, Result, show

@generated function runbench1{fsym, npar, nseq}(::Type{Val{fsym}},
        ::Type{Val{npar}}, ::Type{Val{nseq}}, nloops::Integer, xs, args)
    nargs = nfields(args)
    a(i) = symbol("a", i)
    x(i) = symbol("x", i)
    # inner loop
    stmts = [Expr(:(=), x(i), Expr(:call, fsym, x(i), ntuple(a, nargs)...))
        for i in 1:npar]
    stmts = repeat(stmts, outer=[nseq])
    loop = quote
        t = time_ns()
        for i in 1:nloops
            $(Expr(:block, stmts...))
        end
        t = (time_ns() - t) / 1.0e+9
    end
    # function body
    Expr(:block,
        Expr(:(=), Expr(:tuple, ntuple(a, nargs)...), :args),
        Expr(:(=), Expr(:tuple, ntuple(x, npar)...), :xs),
        loop,
        Expr(:tuple, :t, Expr(:tuple, ntuple(x, npar)...)))
end

function runbench2(fsym::Symbol, npar::Integer, nseq::Integer, nloops::Integer,
        ntries::Integer, x0, args)
    xs = ntuple(i->x0, npar)
    # We use tasks to prevent inlining, and to ensure that the result of the
    # benchmark is used
    # warm up
    t, xs = wait(@schedule runbench1(Val{fsym}, Val{npar}, Val{nseq},
        one(nloops), xs, args))
    times = Array{Float64}(ntries)
    for n in 1:ntries
        t, xs = wait(@schedule runbench1(Val{fsym}, Val{npar}, Val{nseq},
            nloops, xs, args))
        times[n] = t
    end
    avgtime = mean(times)
    mintime = minimum(times)
    maxtime = maximum(times)
    mintime, avgtime, maxtime
end

import Base: show
immutable Config
    npar::Int
    nseq::Int
    nloops::Int
    ntries::Int
end
show(io::IO, c::Config) =
    print(io,
        "npar=$(c.npar) nseq=$(c.nseq) nloops=$(c.nloops) ",
        "ntries=$(c.ntries)")
immutable Result
    mintime::Float64
    avgtime::Float64
    maxtime::Float64
    totaltime::Float64
end
show(io::IO, r::Result) =
    print(io,
        "min=$(@sprintf "%.3f" 1.0e+9*r.mintime) ns   ",
        "avg=$(@sprintf "%.3f" 1.0e+9*r.avgtime) ns   ",
        "max=$(@sprintf "%.3f" 1.0e+9*r.maxtime) ns   ",
        "total=$(@sprintf "%.3f" r.totaltime) s")

function runbench(name::AbstractString, fsym::Symbol, x0, args...;
        ntries::Integer=3, maxunroll::Integer=4, minloop=2, runtime::Real=0.01)
    results = Dict{Config,Result}()
    println("Benchmarking $name:")
    maxlogn = maxunroll
    minlogloop = minloop
    for lognpar in 0:maxlogn
        for lognseq in 0:maxlogn
            for lognloops in minlogloop:30
                npar = 2^lognpar
                nseq = 2^lognseq
                nloops = 2^lognloops
                mintime, avgtime, maxtime =
                    runbench2(fsym, npar, nseq, nloops, ntries, x0, args)
                if mintime >= runtime
                    n = 1.0 * npar * nseq * nloops
                    c = Config(npar, nseq, nloops, ntries)
                    r = Result(mintime/n, avgtime/n, maxtime/n, avgtime)
                    results[c] = r
                    # println(c)
                    # println("    ", r)
                    print(".")
                    break
                end
            end
        end
    end
    if isempty(results)
        println()
        println("*** Could not obtain any results ***")
        println("Most likely, the benchmark kernel is too simple,")
        println("and the optimizer was able to collapse multiple chained invocations.")
        return nothing, results
    end
    lt(cr1, cr2) = cr1[2].mintime < cr2[2].mintime
    minres = sort(collect(results), lt=lt)[1]
    println()
    println("Best result:")
    println("    ", minres[1])
    println("    ", minres[2])
    minres, results
end

macro benchmark(name, f, x0, args...)
    quote
        fsym = gensym(:kernel)
        nargs = length($(esc(args)))
        a(i) = symbol("a", i)
        fundef = Expr(:macrocall, symbol("@inline"),
            Expr(:(=), Expr(:call, fsym, :x, ntuple(a, nargs)...),
                Expr(:block, Expr(:call, $(esc(f)), :x, ntuple(a, nargs)...))))
        eval(AutoBenchmark, fundef)
        $(Expr(:call, :runbench, esc(name), :fsym, esc(x0), map(esc, args)...))
    end
end

end
