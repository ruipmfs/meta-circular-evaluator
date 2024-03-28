function metajulia_repl()
    while true
        print(">> ")
        input = readline()
        if input == "exit"
            empty!(global_scope)
            empty!(function_global_scope)
            break
        end
        try
        parsed = Meta.parse(input)
        incomplete_input = input
        block_depth = 0
        if isa(parsed, Expr)
            block_depth += count_occurrences(input, "begin") + count_occurrences(input, "if") + count_occurrences(input, "for") + count_occurrences(input, "while") + count_occurrences(input, "function")
            block_depth -= count_occurrences(input, "end")
        end
        while isa(parsed, Expr) && (parsed.head == :incomplete || block_depth > 0)
            next_input = readline()
            incomplete_input *= "\n" * next_input
            if isa(parsed, Expr)
                block_depth += count_occurrences(next_input, "begin") + count_occurrences(next_input, "if") + count_occurrences(next_input, "for") + count_occurrences(next_input, "while") + count_occurrences(next_input, "function")
                block_depth -= count_occurrences(next_input, "end")
            end
            parsed = Meta.parse(incomplete_input)
        end
        result = evaluate(parsed)
        if isa(result, String)
            println('"'*"$result"*'"')
        else
            println(result)
        end
        catch e
            println("Error: ", e)
            empty!(global_scope)
            empty!(function_global_scope)
        end
        empty!(temporary_global_scope)
    end
end

function count_occurrences(input_string, substring)
    return count(occursin(substring), split(input_string, "\n"))
end

mutable struct Function
    body::Any
    args::Array{Symbol, 1}
    env::Array{Dict{Symbol,Any},1}
end

Base.show(io::IO, f::Function) = print(io, "<function>")

global_scope = Dict{Symbol,Any}()
let_global_scope = Dict{Symbol,Any}()
function_global_scope = Dict{Symbol, Function}()
let_function_global_scope = Dict{Symbol, Function}()
temporary_global_scope = Array{Dict{Symbol,Any},1}()
global environmentFlag = 0
global globalFlag = 0

function handleIf(expr)  
    i = 1
    while i < length(expr.args)
        condition = evaluate(expr.args[i])
        if condition
            return evaluate(expr.args[i+1])
        else
            i += 2
        end
    end
    return evaluate(expr.args[end])
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
    global environmentFlag = 0
    i = 1
    environmentFlag = 1
    while i < length(expr.args)
        evaluate(expr.args[i])
        i += 1
    end
    result = evaluate(expr.args[i])
    environmentFlag = 0
    empty!(let_global_scope)
    empty!(let_function_global_scope)
    return result
end

function handleGlobal(expr)
    global environmentFlag = 0
    global globalFlag = 0
    i = 1
    globalFlag = 1
    while i < length(expr.args)
        evaluate(expr.args[i])
        i += 1
    end
    result = evaluate(expr.args[i])
    globalFlag = 0
    return result
end

function handleAssociation(expr)
    if isa(expr.args[1], Symbol)
        if environmentFlag == 1
            let_global_scope[expr.args[1]] = evaluate(expr.args[2])
        else
            global_scope[expr.args[1]] = evaluate(expr.args[2])
        end
        result = evaluate(expr.args[2])
        if isa(result, Function)
            delete!(global_scope, expr.args[1])
            function_global_scope[expr.args[1]] = result
            if haskey(function_global_scope, Symbol("anonymous"))
                delete!(function_global_scope, Symbol("anonymous"))
            end
        end
        return result
    else
        if environmentFlag == 1
            let_function_global_scope[expr.args[1].args[1]] = Function(expr.args[2], [], [let_global_scope])
            j=2
            while j <= length(expr.args[1].args)
                push!(let_function_global_scope[expr.args[1].args[1]].args, expr.args[1].args[j])
                j += 1
            end
            return let_function_global_scope[expr.args[1].args[1]]
        else
            if globalFlag == 1
                dict = Dict{Symbol,Any}()
                copy!(dict, let_global_scope)
                function_global_scope[expr.args[1].args[1]] = Function(expr.args[2], [], [global_scope])
                push!(function_global_scope[expr.args[1].args[1]].env, dict)
            else
                function_global_scope[expr.args[1].args[1]] = Function(expr.args[2], [], [global_scope])
            end
            j=2
            while j <= length(expr.args[1].args)
                push!(function_global_scope[expr.args[1].args[1]].args, expr.args[1].args[j])
                j += 1
            end
            return function_global_scope[expr.args[1].args[1]]
        end
    end
end

function handleQuote(expr)
    if isa(expr, Expr)
        if expr.head == :$
            return evaluate(expr.args[1])
        else
            return Expr(expr.head, map(handleQuote, expr.args)...)
        end
    else
        return expr
    end
end

function handleStandardOperations(symb, args)
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
    elseif symb == :(==)
        return args[1] == args[2]
    elseif symb == :!
        return !args[1]
    end
end

function handleNonCallExpressions(expr)
    if expr.head == :&&
        args = map(evaluate, expr.args[1:end])
        if isa(args[1], Bool) && isa(args[2], Bool)
            return args[1] && args[2]
        else
            if !args[1]
                return false
            else
                return evaluate(args[2])
            end
        end
    elseif expr.head == :||
        args = map(evaluate, expr.args[1:end])
        return args[1] || args[2]
    elseif expr.head == :comparison
        return handleComparison(expr)
    elseif expr.head == :if || expr.head == :elseif
        return handleIf(expr)
    elseif expr.head == :block
        if length(expr.args) >= 1
            args = map(evaluate, expr.args[1:end])
            return args[end]
        else
            return
        end
    elseif expr.head == :let
        return handleLet(expr)
    elseif expr.head == :(=)
        return handleAssociation(expr)
    elseif expr.head == :quote
        return handleQuote(expr.args[1])
    elseif expr.head == :->
        return handleAnonymousFunctions(expr)
    elseif expr.head == :global
        return handleGlobal(expr)
    end
end

function handleCallFunctions(expr)
    i = 2
    j = 2
    if (isa(expr.args[1], Expr) && expr.args[1].head == :->)
        handleAnonymousFunctions(expr.args[1])
        callArg = Symbol("anonymous")
    else
        callArg = expr.args[1]
    end
    for dict in reverse(temporary_global_scope)
        if haskey(dict, expr.args[1]) && isa(dict[expr.args[1]], Expr) && dict[expr.args[1]].head == :->
            args = Tuple(map(evaluate, expr.args[2:end]))
            toParse = "($(dict[expr.args[1]]))$args"
            parsed = Meta.parse(toParse)
            return evaluate(parsed)
        elseif haskey(dict, expr.args[1]) && (haskey(function_global_scope, dict[expr.args[1]]) || haskey(let_function_global_scope, dict[expr.args[1]]))
            args = Tuple(map(evaluate, expr.args[2:end]))
            toParse = "($(dict[expr.args[1]]))$args"
            parsed = Meta.parse(toParse)
            return evaluate(parsed)
        end
    end
    if environmentFlag == 1
        func = let_function_global_scope[callArg]
    else
        func = function_global_scope[callArg]
    end
    while i <= length(expr.args)
        dict = Dict{Symbol,Any}()
        if haskey(function_global_scope, expr.args[i]) || haskey(let_function_global_scope, expr.args[i]) || (isa(expr.args[i], Expr) && expr.args[i].head == :->)
            args = expr.args[i]
        else
            args = evaluate(expr.args[i])
        end
        key = func.args[i-1]
        dict[key] = args
        push!(func.env, dict)
        i += 1
    end
    for dict in func.env
        push!(temporary_global_scope, dict)
    end
    result = evaluate(callArg)
    while j <= length(expr.args)
        pop!(func.env)
        pop!(temporary_global_scope)
        j += 1
    end
    if callArg == Symbol("anonymous")
        delete!(function_global_scope, callArg)
    end
    return result
end

function handleAnonymousFunctions(expr)
    params = expr.args[1]
    body = expr.args[2]

    if isa(params, Symbol)
        params = [params]
    elseif params.head == :tuple && length(params.args) == 0
        params = []
    elseif params.head == :tuple
        params = params.args
    end

    if environmentFlag == 1
        dict = Dict{Symbol,Any}()
        copy!(dict, let_global_scope)
        function_global_scope[Symbol("anonymous")] = Function(body, params, [dict])
    else
        function_global_scope[Symbol("anonymous")] = Function(body, params, [global_scope])
    end
    return function_global_scope[Symbol("anonymous")]
end

function evaluate(expr)
    if isa(expr, Number) || isa(expr, String)
        return expr
    elseif isa(expr, Symbol)
        if environmentFlag == 1
            for dict in reverse(temporary_global_scope)
                if haskey(dict, expr)
                    return evaluate(get(dict, expr, nothing))
                end
            end
            if haskey(let_global_scope, expr)
                return evaluate(get(let_global_scope, expr, nothing))
            elseif haskey(let_function_global_scope, expr)
                return evaluate(get(let_function_global_scope, expr, nothing).body)
            end
        else
            for dict in reverse(temporary_global_scope)
                if haskey(dict, expr)
                    return evaluate(get(dict, expr, nothing))
                end
            end
            if haskey(global_scope, expr)
                return evaluate(get(global_scope, expr, nothing))
            elseif haskey(function_global_scope, expr)
                return evaluate(get(function_global_scope, expr, nothing).body)
            end
        end
    elseif isa(expr, Expr)
        if expr.head == :call
            symb = expr.args[1]  
            for dict in reverse(temporary_global_scope)
                if haskey(dict, symb) && (haskey(function_global_scope, dict[symb]) || haskey(let_function_global_scope, dict[symb]) || (isa(dict[symb], Expr) && dict[symb].head == :->))
                    return handleCallFunctions(expr)
                end
            end  
            if haskey(function_global_scope, symb) || haskey(let_function_global_scope, symb) || (isa(symb, Expr) && symb.head == :->)
                return handleCallFunctions(expr)
            else
                args = map(evaluate, expr.args[2:end])
                return handleStandardOperations(symb, args)
            end
        else
            return handleNonCallExpressions(expr)
        end
    elseif isa(expr, QuoteNode)
        return expr.value
    end
end