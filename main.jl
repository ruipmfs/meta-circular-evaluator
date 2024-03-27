function metajulia_repl()
    while true
        print(">> ")
        input = readline()
        if input == "exit"
            empty!(global_scope)
            empty!(function_global_scope)
            break
        end
        #try
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
        #key_list = keys(function_global_scope)
        if isa(result, String)
            println('"'*"$result"*'"')
        else
            found_function = false
            #=for key in key_list
                if function_global_scope[key][1] == result
                    found_function = true
                    break
                end
            end=#
            if found_function
                println('"'*"<function>"*'"')
            else
                println(result)
            end
        end
        #=catch e
            println("Error: ", e)
        end=#
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

global_scope = Dict{Symbol,Any}()
let_global_scope = Dict{Symbol,Any}()
function_global_scope = Dict{Symbol, Function}()
temporary_global_scope = Array{Dict{Symbol,Any},1}()
global environmentFlag = 0

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
    return result
end

function handleAssociation(expr)
    if isa(expr.args[1], Symbol)
        if environmentFlag == 1
            let_global_scope[expr.args[1]] = evaluate(expr.args[2])
        else
            global_scope[expr.args[1]] = evaluate(expr.args[2])
            return evaluate(expr.args[2])
        end
    else
        if environmentFlag == 1
            function_global_scope[expr.args[1].args[1]] = Function(expr.args[2], [expr.args[1].args[2]], [let_global_scope])
            j=3
            while j <= length(expr.args[1].args)
                push!(function_global_scope[expr.args[1].args[1]].args, expr.args[1].args[j])
                j += 1
            end
        else
            function_global_scope[expr.args[1].args[1]] = Function(expr.args[2], [expr.args[1].args[2]], [global_scope])
            j=3
            while j <= length(expr.args[1].args)
                push!(function_global_scope[expr.args[1].args[1]].args, expr.args[1].args[j])
                j += 1
            end
        end
        return ("<function>")
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
    end
end

function handleCallFunctions(expr)
    i = 2
    j = 2
    for dict in reverse(temporary_global_scope)
        if haskey(dict, expr.args[1]) && isa(dict[expr.args[1]], Expr) && dict[expr.args[1]].head == :->
            args = Tuple(map(evaluate, expr.args[2:end]))
            toParse = "($(dict[expr.args[1]]))$args"
            parsed = Meta.parse(toParse)
            return evaluate(parsed)
        elseif haskey(dict, expr.args[1]) && haskey(function_global_scope, dict[expr.args[1]])
            args = Tuple(map(evaluate, expr.args[2:end]))
            toParse = "($(dict[expr.args[1]]))$args"
            parsed = Meta.parse(toParse)
            return evaluate(parsed)
        end
    end
    func = function_global_scope[expr.args[1]]
    while i <= length(expr.args)
        dict = Dict{Symbol,Any}()
        if haskey(function_global_scope, expr.args[i]) || (isa(expr.args[i], Expr) && expr.args[i].head == :->)
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
    result = evaluate(expr.args[1])
    while j <= length(expr.args)
        pop!(func.env)
        j += 1
    end
    return result
end

#=function handleAnonymousFunctions(expr)
    params = expr.args[1].args[1]
    body = expr.args[1].args[2]
    j = 1

    if isa(params, Symbol)
        callArgs = [evaluate(expr.args[2])]
        params = [params]
    elseif params.head == :tuple && length(params.args) == 0
        return evaluate(body)
    elseif params.head == :tuple
        callArgs = map(evaluate, expr.args[2:end])
        params = params.args
    end

    for (param, arg) in zip(params, callArgs)
        evaluatedArg = evaluate(arg)
        push!(temporary_global_scope, Dict{Symbol,Any}(param => evaluatedArg))
    end
    result = evaluate(body)
    while j < length(expr.args[1].args)
        pop!(temporary_global_scope)
        j += 1
    end
    return result
end=#

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
            elseif haskey(function_global_scope, expr)
                return evaluate(get(function_global_scope, expr, nothing).body)
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
                if haskey(dict, symb) && (haskey(function_global_scope, dict[symb]) || (isa(dict[symb], Expr) && dict[symb].head == :->))
                    return handleCallFunctions(expr)
                end
            end     
            if haskey(function_global_scope, symb)
                return handleCallFunctions(expr)
            else
                if isa(symb, Expr) && symb.head == :->
                    return handleAnonymousFunctions(expr)
                else
                    args = map(evaluate, expr.args[2:end])
                    return handleStandardOperations(symb, args)
                end
            end
        else
            return handleNonCallExpressions(expr)
        end
    elseif isa(expr, QuoteNode)
        return expr.value
    end
end