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
            # Check if the input is a function definition.
            if isa(parsed, Expr) && parsed.head == :(=) && isa(parsed.args[1], Expr) && parsed.args[1].head == :call
                println("<function>")
            else
                # Normal evaluation and printing of the result.
                result = eval(parsed)
                println(result)
            end
        catch e
            println("Error: ", e)
        end
        empty!(temporary_global_scope)
        empty!(let_function_global_scope)
        empty!(let_global_scope)
    end
end

function count_occurrences(input_string, substring)
    return count(occursin(substring), split(input_string, "\n"))
end

global_scope = Dict{Symbol,Any}()
function_global_scope = Dict{Symbol,Array{Any,1}}()
temporary_global_scope = Array{Dict{Symbol,Any}, 1}()
let_function_global_scope = Dict{Symbol,Array{Any,1}}()
let_global_scope = Dict{Symbol,Any}()
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
        evaluate(expr.args[1])
        i += 1
    end
    result = evaluate(expr.args[i])
    environmentFlag = 0
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
        i = 2
        if environmentFlag == 1
            let_function_global_scope[expr.args[1].args[1]] = [expr.args[2]]
            while i <= length(expr.args[1].args)
                push!(let_function_global_scope[expr.args[1].args[1]], expr.args[1].args[i])
                i += 1
            end
        else
            function_global_scope[expr.args[1].args[1]] = [expr.args[2]]
            while i <= length(expr.args[1].args)
                push!(function_global_scope[expr.args[1].args[1]], expr.args[1].args[i])
                i += 1
            end
            return evaluate("<function>")
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
    end
end

function handleNonCallExpressions(expr)
    if expr.head == :&&
        args = map(evaluate, expr.args[1:end])
        return args[1] && args[2]
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
        return Expr(:quote, handleQuote(expr.args[1]))
    end
end

function handleCallFunctions(expr)
    i = 2
    j = 2
    auxiliar_funcs = []
    while i <= length(expr.args)
        dict = Dict{Symbol,Any}()
        if haskey(function_global_scope, expr.args[i])
            key = function_global_scope[expr.args[1]][i]
            args = expr.args[i]
            key_args = function_global_scope[args]
            push!(auxiliar_funcs, key)
            function_global_scope[key] = key_args
        else
            args = evaluate(expr.args[i])
        end
        if environmentFlag == 1
            key = let_function_global_scope[expr.args[1]][i]
            let_global_scope[key] = args
        else
            key = function_global_scope[expr.args[1]][i]
            dict[key] = args
            push!(temporary_global_scope, dict)
        end
        i += 1
    end
    result = evaluate(expr.args[1])
    while j <= length(expr.args)
        pop!(temporary_global_scope)
        j += 1
    end
    for key in auxiliar_funcs
        delete!(function_global_scope, key)
    end
    return result
end

function evaluate(expr)
    if isa(expr, Number) || isa(expr, String)
        return expr
    elseif isa(expr, Symbol)
        if environmentFlag == 1
            if haskey(let_global_scope, expr)
                return evaluate(get(let_global_scope, expr, nothing))
            else
                return evaluate(get(let_function_global_scope, expr, nothing)[1])
            end
        else
            for dict in reverse(temporary_global_scope)
                if haskey(dict, expr) && haskey(function_global_scope, expr)
                    return evaluate(get(function_global_scope, expr, nothing)[1])
                elseif haskey(dict, expr)
                    return evaluate(get(dict, expr, nothing))
                end
            end
            if haskey(global_scope, expr)
                return evaluate(get(global_scope, expr, nothing))
            elseif haskey(function_global_scope, expr)
                return evaluate(get(function_global_scope, expr, nothing)[1])
            end
        end
    elseif isa(expr, Expr)
        if expr.head == :call
            symb = expr.args[1]
            if haskey(function_global_scope, symb) || haskey(let_function_global_scope, symb)
                return handleCallFunctions(expr)
            else
                args = map(evaluate, expr.args[2:end])
                return handleStandardOperations(symb, args)
            end
        else
            return handleNonCallExpressions(expr)
        end
    elseif isa(expr, QuoteNode)
        return expr
    end
end