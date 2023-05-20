#####
##### SyntaxTrees
#####

# Avoid piracy by defining AbstractTrees definitions on a wrapper
struct SyntaxNodeWrapper
    node::JuliaSyntax.SyntaxNode
end

function AbstractTrees.children(wrapper::SyntaxNodeWrapper)
    # Don't recurse into these, in order to try to count top-level objects only
    if kind(wrapper.node.raw) in [K"struct", K"call", K"quote", K"=", K"for", K"function"]
        return ()
    else
        map(SyntaxNodeWrapper, JuliaSyntax.children(wrapper.node))
    end
end

#####
##### Parsing files
#####

function parse_file(file_path)
    file = read(file_path, String)
    parsed = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, file)
    return SyntaxNodeWrapper(parsed)
end

#####
##### Do stuff with the parsed files
#####

using JuliaSyntax
using JuliaSyntax: head

function is_method(node)
    k = kind(node)
    # This is a function like function f() 1+1 end
    k == K"function" && return true
    if k == K"="
        # 1-line function definitions like f() = abc...
        # Show up as an `=` with the first argument being a call
        # and the second argument being the function body.
        # We handle those here.
        # We do not handle anonymous functions like `f = () -> 1`
        kids = JuliaSyntax.children(node)
        length(kids) == 2 || return false
        kind(kids[1]) == K"call" || return false
        return true
    end
    return false
end

function get_function_name_if_not_qualified(node) # assumes `is_method(node) == true`
    k = kind(node)

    local f
    # TODO- write this code correctly instead of using try-catch
    try
        if k == K"function"
            f = node.children[1].children[1]
        else
            kids = JuliaSyntax.children(node)
            f = kids[1].children[1]
        end
    catch
        return nothing
    end
    if isnothing(f.children)
        return string(f)
    else
        # Qualified. TODO: handle not qualified but imported (since that isn't defined in the package either).
        return nothing
    end
end

function count_interesting_things(tree::SyntaxNodeWrapper)
    counts = Dict{String,Int}()
    functions = Dict{String,Int}()
    docstring_functions = Dict{String,Int}()
    items = PostOrderDFS(tree)
    foreach(items) do wrapper
        node = wrapper.node
        k = kind(node.raw)
        if is_method(node)
            key = "method"
            function_name = get_function_name_if_not_qualified(node)
            if function_name !== nothing
                functions[function_name] = get(functions, function_name, 0) + 1
            end
            counts[key] = get(counts, key, 0) + 1
        elseif k == K"struct"
            # These we increment once
            key = string(k)
            counts[key] = get(counts, key, 0) + 1
        elseif k == K"export"
            # These we count by the number of their children, since that's the number of exports/packages
            # being handled by that invocation of the keyword
            key = string(k)
            counts[key] = get(counts, key, 0) + length(JuliaSyntax.children(node))
        elseif k == K"doc"
            kids = JuliaSyntax.children(node)
            # When does this happen?
            kind(kids[1].raw) == K"string" || return
            is_method(kids[2]) || return
            key = "method docstring"
            function_name = get_function_name_if_not_qualified(kids[2])
            if function_name !== nothing
                docstring_functions[function_name] = get(docstring_functions, function_name, 0) + 1
            end
            counts[key] = get(counts, key, 0) + 1
        else
            #@show k
        end
    end
    return counts, functions, docstring_functions
end

function print_syntax_counts_summary(io::IO, counts, indent=0)
    total_count = item -> sum(row.count for row in counts if row.item == item; init=0)
    n_struct = total_count("struct")
    n_method = total_count("method")
    n_function = total_count("functions in package")
    n_function_with_docstring = total_count("functions in package with docstrings")
    n_method_docstring = total_count("method docstring")
    n_export = total_count("export")
    n = maximum(ndigits(x) for x in (n_struct, n_method, n_export, n_method_docstring))
    _print = (num, name) -> println(io, " "^indent, "* ", rpad(num, n), " ", name)
    _print(n_export, "exports")
    _print(n_struct, "struct definitions")
    _print(n_method, "method definitions")
    _print(n_method_docstring, "method docstrings")
    _print(n_function, "functions defined in package")
    _print(n_function_with_docstring, "functions defined in package with docstrings")
    return nothing
end

#####
##### Entrypoint
#####

function analyze_syntax_dir(dir)
    table = ParsedCountsEltype[]
    for (root, dirs, files) in walkdir(dir)
        filter!(endswith(".jl"), files)
        functions = Dict{String,Int}()
        docstring_functions = Dict{String,Int}()
        for file_name in files
            path = joinpath(root, file_name)
            tree = parse_file(path)
            file_counts, f, df = count_interesting_things(tree)
            mergewith!(+, functions, f)
            mergewith!(+, docstring_functions, df)
            for (item, count) in file_counts
                push!(table, (; file_name, item, count))
            end
        end
        functions_in_package = length(functions)
        functions_in_package_with_docstrings = length(docstring_functions)
        push!(table, (; file_name="", item="functions in package", count=functions_in_package))
        push!(table, (; file_name="", item="functions in package with docstrings", count=functions_in_package_with_docstrings))
    end
    return table
end
