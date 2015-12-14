module AutoBenchmark

export @benchmark
export Config, Result, show

@generated function runbench1{fsym, npar, nseq}(::Type{Val{fsym}},
        ::Type{Val{npar}}, ::Type{Val{nseq}}, nloops::Integer, xs)
    x(i) = symbol("x", i)
    # inner loop
    stmts = [:($(x(i)) = $fsym($(x(i)))) for i in 1:npar]
    stmts = repeat(stmts, outer=[nseq])
    loop = quote
        t = time_ns()
        for i in 1:nloops
            $(Expr(:block, stmts...))
        end
        t = (time_ns() - t) / 1.0e+9
    end
    # function body
    stmts = []
    push!(stmts, Expr(:(=), Expr(:tuple, ntuple(x, npar)...), :xs))
    push!(stmts, loop)
    push!(stmts, Expr(:tuple, :t, Expr(:tuple, ntuple(x, npar)...)))
    body = Expr(:block, stmts...)
    body
end

function runbench2(fsym::Symbol, npar::Integer, nseq::Integer, nloops::Integer,
        ntries::Integer, x0)
    xs = ntuple(i->x0, npar)
    # We use tasks to prevent inlining, and to ensure that the result of the
    # benchmark is used
    # warm up
    t, xs = wait(@schedule runbench1(Val{fsym}, Val{npar}, Val{nseq}, 1, xs))
    times = Array{Float64}(ntries)
    for n in 1:ntries
        t, xs = wait(@schedule runbench1(Val{fsym}, Val{npar}, Val{nseq},
            nloops, xs))
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

function runbench(name::AbstractString, fsym::Symbol, x0;
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
                    runbench2(fsym, npar, nseq, nloops, ntries, x0)
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
    lt(cr1, cr2) = cr1[2].mintime < cr2[2].mintime
    minres = sort(collect(results), lt=lt)[1]
    println()
    println("Best result:")
    println("    ", minres[1])
    println("    ", minres[2])
    minres, results
end

macro benchmark(name, f, x0)
    quote
        fsym = gensym(:kernel)
        fundef = Expr(:macrocall, symbol("@inline"),
            Expr(:(=), Expr(:call, fsym, :x),
                Expr(:block, Expr(:call, $(esc(f)), :x))))
        eval(AutoBenchmark, fundef)
        runbench($(esc(name)), fsym, $(esc(x0)))
    end
end

end
