
import Test.@testset
import Test.@test

"""
This macro was copied from Suppressor.jl

https://github.com/JuliaIO/Suppressor.jl/blob/master/src/Suppressor.jl
"""
macro capture_out(block)
    quote
        if ccall(:jl_generating_output, Cint, ()) == 0
            original_stdout = stdout
            out_rd, out_wr = redirect_stdout()
            out_reader = @async read(out_rd, String)
        end

        try
            $(esc(block))
        finally
            if ccall(:jl_generating_output, Cint, ()) == 0
                redirect_stdout(original_stdout)
                close(out_wr)
            end
        end

        if ccall(:jl_generating_output, Cint, ()) == 0
            fetch(out_reader)
        else
            ""
        end
    end
end

function test_show(x, repr)
    io = IOBuffer()
    show(io, x)
    String(take!(io)) == repr
end

macro test_with_stdout(expr, expected_output, expected_result)
    quote
        out_val = $expr
        out_text = @capture_out $expr
        out_text == $expected_output && out_val == $expected_result
    end
end

@testset verbose = true "MetaJulia Tests" begin

    @testset verbose = true "Project Statement Tests" begin

        @testset "Basic operations" begin
            @test metajulia_eval(:(1)) == 1
            @test metajulia_eval(:("Hello, World!")) == "Hello, World!"
            @test metajulia_eval(:(1 + 2)) == 3
            @test metajulia_eval(:((2 + 3) * (4 + 5))) == 45
            @test metajulia_eval(:(3 > 2)) == true
            @test metajulia_eval(:(3 < 2)) == false
            @test metajulia_eval(:(3 > 2 && 3 < 2)) == false
            @test metajulia_eval(:(3 > 2 || 3 < 2)) == true
            @test metajulia_eval(:(3 > 2 || 3 < 2)) == true
        end

        @testset "Conditional expressions" begin
            @test metajulia_eval(:(3 > 2 ? 1 : 0)) == 1
            @test metajulia_eval(:(3 < 2 ? 1 : 0)) == 0
            @test metajulia_eval(:(
                if 3 > 2
                    1
                else
                    0
                end
            )) == 1
            @test metajulia_eval(:(
                if 3 < 2
                    1
                elseif 2 > 3
                    2
                else
                    0
                end
            )) == 0
        end

        @testset "Blocks" begin
            @test metajulia_eval(:((1 + 2; 2 * 3; 3 / 4))) == 0.75
            @test metajulia_eval(:(
                begin
                    1 + 2
                    2 * 3
                    3 / 4
                end
            )) == 0.75
        end

        @testset "Let form" begin
            @test metajulia_eval(:(
                let x = 1
                    x
                end
            )) == 1
            @test metajulia_eval(:(
                let x = 2
                    x * 3
                end
            )) == 6
            @test metajulia_eval(:(
                let a = 1, b = 2
                    let a = 3
                        a + b
                    end
                end
            )) == 5
            @test metajulia_eval(:(
                let a = 1
                    a + 2
                end
            )) == 3
        end

        @testset "Let form with functions" begin
            @test metajulia_eval(:(
                let x(y) = y + 1
                    x(1)
                end
            )) == 2
            @test metajulia_eval(:(
                let x(y, z) = y + z
                    x(1, 2)
                end
            )) == 3
            @test metajulia_eval(:(
                let x = 1, y(x) = x + 1
                    y(x + 1)
                end
            )) == 3
        end

        @testset "Assignments" begin
            @test metajulia_eval(:(x = 1 + 2)) == 3
            @test metajulia_eval(:((x = 1 + 2; x + 2))) == 5
            @test test_show(metajulia_eval(:(triple(a) = a + a + a)), "<function>")
            @test metajulia_eval(:((x = 1 + 2; triple(a) = a + a + a; triple(x + 3)))) == 18
            @test metajulia_eval(:((baz = 3))) == 3
            @test metajulia_eval(:(
                begin
                    x = 1 + 2
                    baz = 3
                    let x = 0
                        baz = 5
                    end + baz
                end
            )) == 8
            @test metajulia_eval(:(
                begin
                    baz = 3
                    let
                        baz = 6
                    end + baz
                end
            )) == 9
        end

        @testset "Higher-order functions" begin
            @test test_show(metajulia_eval(:(sum(f, a, b) = a > b ? 0 : f(a) + sum(f, a + 1, b))), "<function>")
            @test metajulia_eval(:(
                begin
                    triple(a) = a + a + a
                    sum(f, a, b) = a > b ? 0 : f(a) + sum(f, a + 1, b)
                    sum(triple, 1, 10)
                end)) == 165
        end

        @testset "Anonymous functions" begin
            @test metajulia_eval(:((x -> x + 1)(2))) == 3
            @test metajulia_eval(:((() -> 5)())) == 5
            @test metajulia_eval(:(((x, y) -> x + y)(1, 2))) == 3
            @test metajulia_eval(:(
                begin
                    sum(f, a, b) = a > b ? 0 : f(a) + sum(f, a + 1, b)
                    sum(x -> x * x, 1, 10)
                end
            )) == 385
            @test test_show(metajulia_eval(:(
                    begin
                        incr = let priv_counter = 0
                            () -> priv_counter = priv_counter + 1
                        end
                    end
                )), "<function>")
            @test metajulia_eval(:(
                begin
                    incr = let priv_counter = 0
                        () -> priv_counter = priv_counter + 1
                    end
                    incr()
                end
            )) == 1
            @test metajulia_eval(:(
                begin
                    incr = let priv_counter = 0
                        () -> priv_counter = priv_counter + 1
                    end
                    incr()
                    incr()
                end
            )) == 2
            @test metajulia_eval(:(
                begin
                    incr = let priv_counter = 0
                        () -> priv_counter = priv_counter + 1
                    end
                    incr()
                    incr()
                    incr()
                end
            )) == 3
        end

        @testset "Global keyword" begin
            @test test_show(metajulia_eval(:(
                    let secret = 1234
                        global show_secret() = secret
                    end
                )), "<function>")
            @test metajulia_eval(:(
                begin
                    let secret = 1234
                        global show_secret() = secret
                    end
                    show_secret()
                end)) == 1234
            @test test_show(metajulia_eval(:(
                    begin
                        let priv_balance = 0
                            global deposit = quantity -> priv_balance = priv_balance + quantity
                            global withdraw = quantity -> priv_balance = priv_balance - quantity
                        end
                    end
                )), "<function>")
            @test metajulia_eval(:(
                begin
                    let priv_balance = 0
                        global deposit = quantity -> priv_balance = priv_balance + quantity
                        global withdraw = quantity -> priv_balance = priv_balance - quantity
                    end
                    deposit(200)
                end
            )) == 200
            @test metajulia_eval(:(
                begin
                    let priv_balance = 0
                        global deposit = quantity -> priv_balance = priv_balance + quantity
                        global withdraw = quantity -> priv_balance = priv_balance - quantity
                    end
                    deposit(200)
                    withdraw(50)
                end
            )) == 150
        end

        @testset "Short-circuit evaluation" begin
            @test test_show(metajulia_eval(:(quotient_or_false(a, b) = !(b == 0) && a / b)), "<function>")
            @test metajulia_eval(:((quotient_or_false(a, b) = !(b == 0) && a / b; quotient_or_false(6, 2)))) == 3.0
            @test metajulia_eval(:((quotient_or_false(a, b) = !(b == 0) && a / b; quotient_or_false(6, 0)))) == false
        end

        @testset verbose = true "Reflection" begin

            @testset "Basic reflection" begin
                @test metajulia_eval(:(:foo)) == :foo
                @test metajulia_eval(:(:(foo + bar))) == :(foo + bar)
                @test metajulia_eval(:(:((1 + 2) * $(1 + 2)))) == :((1 + 2) * 3)
            end

            @testset "fexpr" begin
                @test test_show(metajulia_eval(:(identity_function(x) = x)), "<function>")
                @test metajulia_eval(:((identity_function(x) = x; identity_function(1 + 2)))) == 3
                @test test_show(metajulia_eval(:(identity_fexpr(x) := x)), "<fexpr>")
                @test metajulia_eval(:((identity_fexpr(x) := x; identity_fexpr(1 + 2)))) == :(1 + 2)
                @test metajulia_eval(:((identity_fexpr(x) := x; identity_fexpr(1 + 2) == :(1 + 2)))) == true
            end

            @testset "fexpr with eval" begin
                @test test_show(metajulia_eval(:(
                        begin
                            debug(expr) := let r = eval(expr)
                                println(expr, " => ", r)
                                r
                            end
                        end
                    )), "<fexpr>")

                @test @test_with_stdout(metajulia_eval(:(
                        begin
                            debug(expr) := let r = eval(expr)
                                println(expr, " => ", r)
                                r
                            end
                            let x = 1
                                1 + debug(x + 1)
                            end
                        end
                    )), "x + 1 => 2\n", 3)
            end

            @testset "fexpr with eval - scope" begin
                @test test_show(metajulia_eval(:(
                        begin
                            let a = 1
                                global puzzle(x) :=
                                    let b = 2
                                        eval(x) + a + b
                                    end
                            end
                        end
                    )), "<fexpr>")

                @test metajulia_eval(:(
                    begin
                        let a = 1
                            global puzzle(x) :=
                                let b = 2
                                    eval(x) + a + b
                                end
                        end
                        let a = 3, b = 4
                            puzzle(a + b)
                        end
                    end
                )) == 10

                @test metajulia_eval(:(
                    begin
                        let a = 1
                            global puzzle(x) :=
                                let b = 2
                                    eval(x) + a + b
                                end
                        end
                        let eval = 123
                            puzzle(eval)
                        end
                    end
                )) == 126
            end

            @testset "fexpr - when" begin
                @test test_show(metajulia_eval(:(
                        begin
                            when(condition, action) := eval(condition) ? eval(action) : false
                        end
                    )), "<fexpr>")
                @test test_show(metajulia_eval(:(
                        begin
                            when(condition, action) := eval(condition) ? eval(action) : false
                            show_sign(n) =
                                begin
                                    when(n > 0, println("Positive"))
                                    when(n < 0, println("Negative"))
                                    n
                                end
                        end
                    )), "<function>")
                @test @test_with_stdout(metajulia_eval(:(
                        begin
                            when(condition, action) := eval(condition) ? eval(action) : false
                            show_sign(n) =
                                begin
                                    when(n > 0, println("Positive"))
                                    when(n < 0, println("Negative"))
                                    n
                                end
                            show_sign(3)
                        end
                    )), "Positive\n", 3)
                @test @test_with_stdout(metajulia_eval(:(
                        begin
                            when(condition, action) := eval(condition) ? eval(action) : false
                            show_sign(n) =
                                begin
                                    when(n > 0, println("Positive"))
                                    when(n < 0, println("Negative"))
                                    n
                                end
                            show_sign(-3)
                        end
                    )), "Negative\n", -3)
                @test @test_with_stdout(metajulia_eval(:(
                        begin
                            when(condition, action) := eval(condition) ? eval(action) : false
                            show_sign(n) =
                                begin
                                    when(n > 0, println("Positive"))
                                    when(n < 0, println("Negative"))
                                    n
                                end
                            show_sign(0)
                        end
                    )), "", 0)
            end

            @testset "fexpr - repeat_until" begin
                @test test_show(metajulia_eval(:(
                        begin
                            repeat_until(condition, action) :=
                                let
                                    loop() = (eval(action); eval(condition) ? false : loop())
                                    loop()
                                end
                        end
                    )), "<fexpr>")
                @test @test_with_stdout(metajulia_eval(:(
                        begin
                            repeat_until(condition, action) :=
                                let
                                    loop() = (eval(action); eval(condition) ? false : loop())
                                    loop()
                                end
                            let n = 4
                                repeat_until(n == 0, (println(n); n = n - 1))
                            end
                        end
                    )), "4\n3\n2\n1\n", false)
            end

            @testset "fexpr - mystery" begin
                @test test_show(metajulia_eval(:(mystery() := eval)), "<fexpr>")
                @test test_show(metajulia_eval(:(
                        begin
                            mystery() := eval
                            let a = 1, b = 2
                                global eval_here = mystery()
                            end
                        end
                    )), "<function>")
                @test test_show(metajulia_eval(:(
                        begin
                            mystery() := eval
                            let a = 3, b = 4
                                global eval_there = mystery()
                            end
                        end
                    )), "<function>")
                @test metajulia_eval(:(
                    begin
                        mystery() := eval
                        let a = 1, b = 2
                            global eval_here = mystery()
                        end
                        let a = 3, b = 4
                            global eval_there = mystery()
                        end
                        eval_here(:(a + b)) + eval_there(:(a + b))
                    end
                )) == 10
            end

        end

        @testset verbose = true "Metaprogramming" begin

            @testset "macro" begin
                @test test_show(metajulia_eval(Meta.parse("when(condition, action) \$= :(\$condition ? \$action : false)")), "<macro>")
            end

            @testset "macro - abs" begin
                @test test_show(metajulia_eval(Meta.parse("""begin
                                                             when(condition, action) \$= :(\$condition ? \$action : false)
                                                             abs(x) = (when(x < 0, (x = -x;)); x)
                                                             end""")), "<function>")
                @test metajulia_eval(Meta.parse("""begin
                                                   when(condition, action) \$= :(\$condition ? \$action : false)
                                                   abs(x) = (when(x < 0, (x = -x;)); x)
                                                   abs(-5)
                                                   end""")) == 5
                @test metajulia_eval(Meta.parse("""begin
                                                   when(condition, action) \$= :(\$condition ? \$action : false)
                                                   abs(x) = (when(x < 0, (x = -x;)); x)
                                                   abs(5)
                                                   end""")) == 5

            end

            @testset "macro - repeat_until" begin

                @test test_show(metajulia_eval(Meta.parse("""begin
                                                             repeat_until(condition, action) \$=
                                                                :(let ;
                                                                    loop() = (\$action; \$condition ? false : loop())
                                                                    loop()
                                                                end)
                                                             end""")), "<macro>")
                @test @test_with_stdout(metajulia_eval(Meta.parse("""begin
                                                                        repeat_until(condition, action) \$=
                                                                            :(let ;
                                                                                loop() = (\$action; \$condition ? false : loop())
                                                                                loop()
                                                                            end)
                                                                        let n = 4
                                                                            repeat_until(n == 0, (println(n); n = n - 1))
                                                                        end
                                                                     end""")), "4\n3\n2\n1\n", false)
                @test @test_with_stdout(metajulia_eval(Meta.parse("""begin
                                                                     repeat_until(condition, action) \$=
                                                                        :(let ;
                                                                            loop() = (\$action; \$condition ? false : loop())
                                                                            loop()
                                                                        end)
                                                                        let loop = "I'm looping!", i = 3
                                                                            repeat_until(i == 0, (println(loop); i = i - 1))
                                                                        end
                                                                     end""")), "<function>\n<function>\n<function>\n", false)
            end

            @testset "macro - repeat_until with gensym" begin
                @test test_show(metajulia_eval(Meta.parse("""begin
                                                             repeat_until(condition, action) \$=
                                                             let loop = gensym()
                                                               :(let ;
                                                                    \$loop() = (\$action; \$condition ? false : \$loop())
                                                                    \$loop()
                                                                end)
                                                              end
                                                              end""")), "<macro>")
                @test @test_with_stdout(metajulia_eval(Meta.parse("""begin
                                                                     repeat_until(condition, action) \$=
                                                                     let loop = gensym()
                                                                        :(let ;
                                                                            \$loop() = (\$action; \$condition ? false : \$loop())
                                                                            \$loop()
                                                                        end)
                                                                     end
                                                                        let loop = "I'm looping!", i = 3
                                                                            repeat_until(i == 0, (println(loop); i = i - 1))
                                                                        end
                                                                     end""")), "I'm looping!\nI'm looping!\nI'm looping!\n", false)

            end

        end

    end

    @testset "Extra Tests" begin

        @test metajulia_eval(:(
            begin
                a = 1
                let a = 2, b = a
                    b
                end
            end
        )) == 2

    end

end;
