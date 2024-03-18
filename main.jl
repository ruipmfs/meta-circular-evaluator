function metajulia_repl()
    while true
        print(">> ")
        input = readline()
        if input == "exit"
            empty!(global_scope)
            empty!(function_global_scope)
            break
        end
        parsed = Meta.parse(input)
        incomplete_input = input
        while parsed.head == :incomplete 
            print(">> ")
            next_input = readline()
            incomplete_input *= next_input
            parsed = Meta.parse(incomplete_input)
            if parsed.head != :incomplete
                println(parsed)
            end
        end
        println(evaluate(parsed))
        empty!(temporary_global_scope)
        empty!(let_function_global_scope)
        empty!(let_global_scope)
    end
end

global_scope = Dict{Symbol,Any}()
function_global_scope = Dict{Symbol,Array{Any,1}}()
temporary_global_scope = Dict{Symbol,Any}()
let_function_global_scope = Dict{Symbol,Array{Any,1}}()
let_global_scope = Dict{Symbol,Any}()
global environmentFlag = 0

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
    end
end

function handleCallFunctions(expr)
    i = 2
    function_ids = []
    while i <= length(expr.args)
        if haskey(function_global_scope, expr.args[i])
            push!(function_ids, i) 
        else
            args = evaluate(expr.args[i])
            if environmentFlag == 1
                key = let_function_global_scope[expr.args[1]][i]
                let_global_scope[key] = args
            else
                key = function_global_scope[expr.args[1]][i]
                temporary_global_scope[key] = args
            end
        end
        i += 1
    end
    for id in function_ids
        args = evaluate(expr.args[id])
        if environmentFlag == 1
            key = let_function_global_scope[expr.args[1]][id]
            let_global_scope[key] = args
        else
            key = function_global_scope[expr.args[1]][id]
            temporary_global_scope[key] = args
        end
    end
    return evaluate(expr.args[1])
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
            if haskey(temporary_global_scope, expr)
                return evaluate(get(temporary_global_scope, expr, nothing))
            elseif haskey(global_scope, expr)
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
    end
end