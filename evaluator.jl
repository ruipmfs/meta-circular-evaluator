function metajulia_repl()
    print(">> ")
    input = readline()
    output = eval(Meta.parse(input))
    println(output)
    metajulia_repl()
end

function eval(exp)
    if self_evaluating(exp)
        exp
    elseif is_adition(exp)
        sum(eval.(exp.args[2:end]))
    elseif is_product(exp)
        prod(eval.(exp.args[2:end]))
    elseif is_subtraction(exp)
        eval(first_operand(exp)) - eval(second_operand(exp))
    elseif is_division(exp)
        eval(first_operand(exp)) / eval(second_operand(exp))
    elseif is_bigger(exp)
        eval(first_operand(exp)) > eval(second_operand(exp))
    elseif is_smaller(exp)
        eval(first_operand(exp)) < eval(second_operand(exp))
    elseif is_and(exp)
        eval(first_operand(exp)) ? eval(second_operand(exp)) : false
    elseif is_or(exp)
        eval(first_operand(exp)) ? true : eval(second_operand(exp))
    elseif is_if(exp)
        eval(first_operand(exp)) ? eval(second_operand(exp)) : eval(third_operand(exp))
    elseif is_block(exp)
        eval(exp.args[length(exp.args)])
    elseif is_comparison(exp)
        result = []
        for i in 1:2:length(exp.args) - 2
            push!(result, eval(Expr(:call, exp.args[i+1], exp.args[i], exp.args[i+2])))
        end
        reduce(&, result)
    else
        "Unknown expression type -- EVAL"
    end
end

self_evaluating(exp) = isa(exp, String) || isa(exp, Int64)
is_adition(exp) = exp.head == :call && exp.args[1] == :+
is_product(exp) = exp.head == :call && exp.args[1] == :*
is_subtraction(exp) = exp.head == :call && exp.args[1] == :-
is_division(exp) = exp.head == :call && exp.args[1] == :/
is_bigger(exp) = exp.head == :call && exp.args[1] == :>
is_smaller(exp) = exp.head == :call && exp.args[1] == :<
is_and(exp) = exp.head == :&&
is_or(exp) = exp.head == :||
is_if(exp) = exp.head == :if
is_block(exp) = exp.head == :block
is_comparison(exp) = exp.head == :comparison
first_operand(exp) = exp.head == :call ? exp.args[2] : exp.args[1]
second_operand(exp) = exp.head == :call ? exp.args[3] : exp.args[2]
third_operand(exp) = exp.args[3]
