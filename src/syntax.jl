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

function count_interesting_things(tree::SyntaxNodeWrapper)
    counts = Dict{String,Int}()
    items = PostOrderDFS(tree)
    foreach(items) do wrapper
        k = kind(wrapper.node.raw)
        if is_method(wrapper.node)
            key = "method"
            counts[key] = get(counts, key, 0) + 1
        elseif k == K"struct"
            # These we increment once
            key = string(k)
            counts[key] = get(counts, key, 0) + 1
        elseif k == K"export"
            # These we count by the number of their children, since that's the number of exports/packages
            # being handled by that invocation of the keyword
            key = string(k)
            counts[key] = get(counts, key, 0) + length(JuliaSyntax.children(wrapper.node))
        elseif k == K"doc"
            kids = JuliaSyntax.children(wrapper.node)
            # When does this happen?
            kind(kids[1].raw) == K"string" || return
            is_method(kids[2]) || return
            key = "method docstring"
            counts[key] = get(counts, key, 0) + 1
        else
            #@show k
        end
    end
    return counts
end

function print_syntax_counts_summary(io::IO, counts, indent=0)
    total_count = item -> sum(row.count for row in counts if row.item == item; init=0)
    n_struct = total_count("struct")
    n_method = total_count("method")
    n_method_docstring = total_count("method docstring")
    n_export = total_count("export")
    n = maximum(ndigits(x) for x in (n_struct, n_method, n_export, n_method_docstring))
    _print = (num, name) -> println(io, " "^indent, "* ", rpad(num, n), " ", name)
    _print(n_export, "exports")
    _print(n_struct, "struct definitions")
    _print(n_method, "method definitions")
    _print(n_method_docstring, "method docstrings")
    return nothing
end

#####
##### Entrypoint
#####

function analyze_syntax_dir(dir)
    table = ParsedCountsEltype[]
    for (root, dirs, files) in walkdir(dir)
        filter!(endswith(".jl"), files)
        for file_name in files
            path = joinpath(root, file_name)
            tree = parse_file(path)
            file_counts = count_interesting_things(tree)
            for (item, count) in file_counts
                push!(table, (; file_name, item, count))
            end
        end
    end
    return table
end
