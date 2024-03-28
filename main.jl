function metajulia_repl()
    while true
        print(">> ")
        input = readline()
        if input == "exit"
            # Clear global environments upon exiting.
            empty!(global_scope)
            empty!(function_global_scope)
            break
        end
        try
            # Parse the input to check for completeness and block structure.
            parsed = Meta.parse(input)
            incomplete_input = input
            block_depth = 0
            # Count the depth based on block starting and ending keywords.
            if isa(parsed, Expr)
                block_depth += count_occurrences(input, "begin") + count_occurrences(input, "if") + count_occurrences(input, "for") + count_occurrences(input, "while") + count_occurrences(input, "function")
                block_depth -= count_occurrences(input, "end")
            end
            # Keep reading lines until the input is complete.
            while isa(parsed, Expr) && (parsed.head == :incomplete || block_depth > 0)
                next_input = readline()
                incomplete_input *= "\n" * next_input
                if isa(parsed, Expr)
                    block_depth += count_occurrences(next_input, "begin") + count_occurrences(next_input, "if") + count_occurrences(next_input, "for") + count_occurrences(next_input, "while") + count_occurrences(next_input, "function")
                    block_depth -= count_occurrences(next_input, "end")
                end
                parsed = Meta.parse(incomplete_input)
            end
            # Evaluate the parsed expression.
            result = metajulia_eval(parsed)
            if isa(result, String)
                println('"'*"$result"*'"')
            else
                println(result)
            end
        catch e
            println("Error: ", e)
            # Clear environments upon error.
            empty!(global_scope)
            empty!(function_global_scope)
        end
        empty!(temporary_global_scope)
    end
end

# Count occurrences of a substring in a string, split by lines.
function count_occurrences(input_string, substring)
    return count(occursin(substring), split(input_string, "\n"))
end

mutable struct Function
    body::Any
    args::Array{Symbol, 1}
    env::Array{Dict{Symbol,Any},1}
end

mutable struct Macro
    body::Any
    args::Array{Symbol, 1}
    env::Array{Dict{Symbol,Any},1}
end

mutable struct Fexpr
    body::Any
    args::Array{Symbol, 1}
    env::Array{Dict{Symbol,Any},1}
end

# Correct interpretation of functions, macros and fexpr
Base.show(io::IO, f::Function) = print(io, "<function>")
Base.show(io::IO, f::Macro) = print(io, "<macro>")
Base.show(io::IO, f::Fexpr) = print(io, "<fexpr>")

global_scope = Dict{Symbol,Any}()
let_global_scope = Dict{Symbol,Any}()
function_global_scope = Dict{Symbol, Any}()
let_function_global_scope = Dict{Symbol, Any}()
temporary_global_scope = Array{Dict{Symbol,Any},1}()
fexpr_global_scope = Dict{Symbol, Fexpr}()
global environmentFlag = 0
global globalFlag = 0
global isFexpr = 0

function handleIf(expr)  
    i = 1
    while i < length(expr.args)
        condition = metajulia_eval(expr.args[i])
        if condition
            return metajulia_eval(expr.args[i+1])
        else
            i += 2
        end
    end
    return metajulia_eval(expr.args[end])
end

function handleComparison(expr)
    i = 3
    new_expr = Expr(:call, expr.args[2], expr.args[1], expr.args[3])
    while i < length(expr.args)
        new_expr = Expr(:&&, new_expr, Expr(:call, expr.args[i+1], expr.args[i], expr.args[i+2]))
        i += 2
    end
    args = map(metajulia_eval, new_expr.args[1:end])
    return args[1] && args[2]
end

function handleLet(expr)
    global environmentFlag = 0
    i = 1
    environmentFlag = 1
    while i < length(expr.args)
        metajulia_eval(expr.args[i])
        i += 1
    end
    result = metajulia_eval(expr.args[i])
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
        metajulia_eval(expr.args[i])
        i += 1
    end
    result = metajulia_eval(expr.args[i])
    globalFlag = 0
    return result
end

function handleAssociation(expr)
    # Handle simple attribuitons
    if isa(expr.args[1], Symbol)
        if environmentFlag == 1
            let_global_scope[expr.args[1]] = metajulia_eval(expr.args[2])
        else
            global_scope[expr.args[1]] = metajulia_eval(expr.args[2])
        end
        result = metajulia_eval(expr.args[2])
        # Handle Anonymous functions
        if isa(result, Function)
            delete!(global_scope, expr.args[1])
            function_global_scope[expr.args[1]] = result
            if haskey(function_global_scope, Symbol("anonymous"))
                delete!(function_global_scope, Symbol("anonymous"))
            end
        end
        return result
    else
        # Handle function creation
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

function handleFexpr(expr)
    fexpr_global_scope[expr.args[1].args[1]] = Fexpr(expr.args[2], [expr.args[1].args[2]], [global_scope])
    i=3
    while i <= length(expr.args[1].args)
        push!(fexpr_global_scope[expr.args[1].args[1]].args, expr.args[1].args[i])
        i += 1
    end
    return fexpr_global_scope[expr.args[1].args[1]]
end

function handleQuote(expr)
    if isa(expr, Expr)
        if expr.head == :$
            return metajulia_eval(expr.args[1])
        else
            return Expr(expr.head, map(handleQuote, expr.args)...)
        end
    else
        return expr
    end
end

function handleMacro(expr)
    macro_body = Meta.parse(replace("$(expr.args[2])", "\$" => "")[2:end])
    # If it is inside of a let (environment) take the let scope instead of the global
    if environmentFlag == 1 
        new_macro = Macro(macro_body, [], [let_global_scope])
    else
        new_macro = Macro(macro_body, [], [global_scope])
    end
    i=2
    while i <= length(expr.args[1].args)
        push!(new_macro.args, expr.args[1].args[i])
        i += 1
    end
     # If it is inside of a let (environment) take the let scope instead of the global
    if environmentFlag == 1
        let_function_global_scope[expr.args[1].args[1]] = new_macro
    else
        function_global_scope[expr.args[1].args[1]] = new_macro
    end
    return new_macro
end

function handleStandardOperations(symb, args)
    if symb == :+
        return sum(args)
    elseif symb == :-
        if length(args) >= 2
            return foldl(-, args)
        else
            # Handle symetric input
            push!(args, -1)
            return prod(args)
        end
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
        args = map(metajulia_eval, expr.args[1:end])
        if isa(args[1], Bool) && isa(args[2], Bool)
            return args[1] && args[2]
        # Handle short-circuit evaluation
        else
            if !args[1]
                return false
            else
                return metajulia_eval(args[2])
            end
        end
    elseif expr.head == :||
        args = map(metajulia_eval, expr.args[1:end])
        return args[1] || args[2]
    elseif expr.head == :comparison
        return handleComparison(expr)
    elseif expr.head == :if || expr.head == :elseif
        return handleIf(expr)
    elseif expr.head == :block
        if length(expr.args) >= 1
            args = map(metajulia_eval, expr.args[1:end])
            return args[end]
        else
            return
        end
    elseif expr.head == :let
        return handleLet(expr)
    elseif expr.head == :(=)
        return handleAssociation(expr)
    elseif  expr.head == :(:=)
        return handleFexpr(expr)
    elseif expr.head == :quote
        return handleQuote(expr.args[1])
    elseif expr.head == :->
        return handleAnonymousFunctions(expr)
    elseif expr.head == :global
        return handleGlobal(expr)
    elseif expr.head == :($=)
        return handleMacro(expr)
    end
end

function handleCallFunctions(expr)
    i = 2
    j = 2
    # Handle call of an Anonymous function
    if (isa(expr.args[1], Expr) && expr.args[1].head == :->)
        handleAnonymousFunctions(expr.args[1])
        callArg = Symbol("anonymous")
    else
        # Function name
        callArg = expr.args[1]
    end
    # Handle invocation of a function that is given as an argument to a main function
    for dict in reverse(temporary_global_scope)
        if haskey(dict, callArg) && isa(dict[callArg], Expr) && dict[callArg].head == :->
            args = Tuple(map(metajulia_eval, expr.args[2:end]))
            toParse = "($(dict[callArg]))$args"
            parsed = Meta.parse(toParse)
            return metajulia_eval(parsed)
        elseif haskey(dict, callArg) && (haskey(function_global_scope, dict[callArg]) || haskey(let_function_global_scope, dict[callArg]))
            args = Tuple(map(metajulia_eval, expr.args[2:end]))
            toParse = "($(dict[callArg]))$args"
            parsed = Meta.parse(toParse)
            return metajulia_eval(parsed)
        end
    end
    if environmentFlag == 1
        if haskey(let_function_global_scope, callArg)
            func = let_function_global_scope[callArg]
        else
            func = fexpr_global_scope[callArg]
        end
    else
        if haskey(function_global_scope, callArg)
            func = function_global_scope[callArg]
        else
            func = fexpr_global_scope[callArg]
        end
    end
    while i <= length(expr.args)
        dict = Dict{Symbol,Any}()
        # Handle function that is given as an argument to a main function
        if haskey(function_global_scope, expr.args[i]) || haskey(let_function_global_scope, expr.args[i]) ||
            (haskey(function_global_scope, callArg) && isa(function_global_scope[callArg], Macro)) || 
            (haskey(let_function_global_scope, callArg) && isa(let_function_global_scope[callArg], Macro)) || 
            (isa(expr.args[i], Expr) && expr.args[i].head == :->) || haskey(fexpr_global_scope, callArg)
            args = expr.args[i]
        else
            args = metajulia_eval(expr.args[i])
        end
        # Store function environment 
        key = func.args[i-1]
        dict[key] = args
        push!(func.env, dict)
        i += 1
    end
    # Handle temporary dictionary of a macro that is given as an argument to a main function
    if (haskey(function_global_scope, callArg) && isa(function_global_scope[callArg], Macro)) ||
        (haskey(let_function_global_scope, callArg) && isa(let_function_global_scope[callArg], Macro))
        for dict in func.env
            pushfirst!(temporary_global_scope, dict)
        end
    else
        for dict in func.env
            push!(temporary_global_scope, dict)
        end
    end
    result = metajulia_eval(callArg)
    # Delete of temporary arguments from temporary dictionary and function environment
    while j <= length(expr.args)
        pop!(func.env)
        pop!(temporary_global_scope)
        j += 1
    end
    # Delete of temporary anonymous function
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

function metajulia_eval(expr)
    if isa(expr, Number) || isa(expr, String)
        return expr
    elseif isa(expr, Symbol)
        if environmentFlag == 1
            for dict in reverse(temporary_global_scope)
                if haskey(dict, expr)
                    #if isFexpr == 0
                    return metajulia_eval(get(dict, expr, nothing))
                    #else
                    #    return get(dict, expr, nothing)
                    #end
                end
            end
            if haskey(let_global_scope, expr)
                return metajulia_eval(get(let_global_scope, expr, nothing))
            elseif haskey(let_function_global_scope, expr)
                return metajulia_eval(get(let_function_global_scope, expr, nothing).body)
            #elseif haskey(fexpr_global_scope, expr)
            #    global isFexpr = 1
            #    fexpr_scope = get(fexpr_global_scope, expr, nothing).env
            #    fexpr_global_scope[expr].env = temporary_global_scope
            #    result = metajulia_eval(get(fexpr_global_scope, expr, nothing).body)
            #    fexpr_global_scope[expr].env = fexpr_scope
            #    global isFexpr = 0
            #    return result
            end
        else
            for dict in reverse(temporary_global_scope)
                if haskey(dict, expr)
                #    if isFexpr == 0
                    return metajulia_eval(get(dict, expr, nothing))
                #    else
                #        return get(dict, expr, nothing)
                #    end
                end
            end
            if haskey(global_scope, expr)
                return metajulia_eval(get(global_scope, expr, nothing))
            elseif haskey(function_global_scope, expr)
                return metajulia_eval(get(function_global_scope, expr, nothing).body)
            #elseif haskey(fexpr_global_scope, expr)
            #    global isFexpr = 1
            #    fexpr_scope = get(fexpr_global_scope, expr, nothing).env
            #    fexpr_global_scope[expr].env = temporary_global_scope
            #    result = metajulia_eval(get(fexpr_global_scope, expr, nothing).body)
            #    fexpr_global_scope[expr].env = fexpr_scope
            #    global isFexpr = 0
            #    return result
            end
        end
    elseif isa(expr, Expr)
        if expr.head == :call
            symb = expr.args[1]
            #=
            if symb == :eval
                return metajulia_eval(expr.args[2])
            elseif symb == :println
                str = ""
                i = 2
                while i <= length(expr.args)
                    str *= "$(metajulia_eval(expr.args[i]))"
                    i+=1
                end
                return metajulia_eval(str)
            end 
            =#
            for dict in reverse(temporary_global_scope)
                if haskey(dict, symb) && (haskey(function_global_scope, dict[symb]) || haskey(let_function_global_scope, dict[symb]) || (isa(dict[symb], Expr) && dict[symb].head == :->))
                    return handleCallFunctions(expr)
                end
            end  
            if haskey(function_global_scope, symb) || haskey(let_function_global_scope, symb) || (isa(symb, Expr) && symb.head == :->) || haskey(fexpr_global_scope, symb)
                return handleCallFunctions(expr)
            else
                args = map(metajulia_eval, expr.args[2:end])
                return handleStandardOperations(symb, args)
            end
        else
            return handleNonCallExpressions(expr)
        end
    elseif isa(expr, QuoteNode)
        return expr.value
    end
end