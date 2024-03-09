function metajulia_repl()
    print(">> ")
    input = readline()
    parsed = Meta.parse(input)
    println(evaluate(parsed))
    metajulia_repl()
end

global_scope = Dict{Symbol, Any}()

function handleIf(expr)
    i = 1
    args = map(evaluate, expr.args[1:end])
    while i < length(args)
        condition = evaluate(args[1])
        if condition
            return args[2]
        else
            i += 2
        end
    end
    return map(evaluate, args[end])
end

function handleComparison(expr)
    i = 3
    new_expr = Expr(:call, expr.args[2], expr.args[1], expr.args[3])
    while i < length(expr.args)
        new_expr = Expr(:&&, new_expr, Expr(:call, expr.args[i+1], expr.args[i], expr.args[i+2]))
        i += 2
    end
    args = map(evaluate, new_expr.args[1:end])
    return args[1] && args[2]
end

function handleLet(expr)
    if isa(expr.args[1].args[1], Expr)
        i = 1
        while i <= length(expr.args[1].args)
            global_scope[expr.args[1].args[i].args[1]] = expr.args[1].args[i].args[2]
            i += 1
        end 
    else
        global_scope[expr.args[1].args[1]] = expr.args[1].args[2]
    end
    return evaluate(expr.args[end])
end

function handle_standard_operations(symb, args)
    if symb == :+
        return sum(args)
    elseif symb == :-
        return foldl(-, args)
    elseif symb == :*
        return prod(args)
    elseif symb == :/
        return foldl(/, args)
    elseif symb == :>
        return args[1] > args[2]
    elseif symb == :<
        return args[1] < args[2]
    end
end

function handle_non_call_expressions(expr)
    if expr.head == :&&
        args = map(evaluate, expr.args[1:end])
        return args[1] && args[2]
    elseif expr.head == :||
        args = map(evaluate, expr.args[1:end])
        return args[1] || args[2]
    elseif expr.head == :comparison
        handleComparison(expr)
    elseif expr.head == :if || expr.head == :elseif
        handleIf(expr)
    elseif expr.head == :block
        args = map(evaluate, expr.args[1:end])
        return args[end]
    elseif expr.head == :let
        return handleLet(expr)
    end
end

function evaluate(expr)
    if isa(expr, Number) || isa(expr, String)
        return expr
    elseif isa(expr, Symbol)
        return get(global_scope, expr, nothing)
    elseif isa(expr, Expr)
        if expr.head == :call
            symb = expr.args[1]
            args = map(evaluate, expr.args[2:end])
            return handle_standard_operations(symb, args)
        else
            return handle_non_call_expressions(expr)
        end
    end
end