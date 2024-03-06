function metajulia_repl()
    println(">> ")
    input = readline()
    parsed = Meta.parse(input)
    println(evaluate(parsed))
    metajulia_repl()
end

function evaluate(expr)
    if isa(expr, Number) || isa(expr, String)
        return expr
    elseif isa(expr, Expr)
        if expr.head == :call
            symb = expr.args[1]
            args = map(evaluate, expr.args[2:end])
            if symb == :+
                return sum(args)
            elseif symb == :*
                return prod(args)
            elseif symb == :>
                return args[1] > args[2]
            elseif symb == :<
                return args[1] < args[2]
            end
        elseif expr.head == :&&
            args = map(evaluate, expr.args[1:end])
            return args[1] && args[2]
        elseif expr.head == :||
            args = map(evaluate, expr.args[1:end])
            return args[1] || args[2]
        end
    end
end