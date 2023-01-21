export analyze_syntax

#####
##### SyntaxTrees
#####

# Avoid piracy by defining AbstractTrees definitions on a wrapper
struct SyntaxNodeWrapper
    node::JuliaSyntax.SyntaxNode
end

function AbstractTrees.children(wrapper::SyntaxNodeWrapper)
    # Don't recurse into these, in order to try to count top-level objects only
    if kind(wrapper.node.raw) in [ K"struct", K"call", K"quote", K"=", K"for", K"function"]
        return ()
    else
        map(SyntaxNodeWrapper, JuliaSyntax.children(wrapper.node))
    end
end

#####
##### Parsing files, traversing literal include statements
#####

function parse_syntax_one(file_path)
    file = read(file_path, String)
    parsed = JuliaSyntax.parse(JuliaSyntax.SyntaxNode, file)
    return SyntaxNodeWrapper(parsed[1])
end


function find_literal_includes(tree::SyntaxNodeWrapper)
    items = PostOrderDFS(tree)

    # Filter to includes
    itr = Iterators.filter(items) do wrapper
        # A literal include has kind `K"call"`, whose first children's value is the symbol `:include`,
        # and whose second child is the thing being included, which we require to be a string literal
        k = kind(wrapper.node.raw)
        k == K"call" || return false
        kids = JuliaSyntax.children(wrapper.node)
        isempty(kids) && return false
        if kids[1].val == Symbol(:include) && kind(kids[2].raw) == K"string"
            return true
        else
            return false
        end
        return true
    end

    # Grab the filenames
    return map(itr) do wrapper
        kids = JuliaSyntax.children(wrapper.node)
        return only(kids[2].val).val
    end
end

function parse_syntax_recursive(file_path)
    trees = Pair{String, SyntaxNodeWrapper}[]
    tree = parse_syntax_one(file_path)
    push!(trees, basename(file_path) => tree)
    other_files = find_literal_includes(tree)
    for file in other_files
        full_path = joinpath(dirname(file_path), file)
        more_trees = parse_syntax_recursive(full_path)
        append!(trees, more_trees)
    end
    return trees
end

function parse_syntax_recursive(pkg::Module)
    file_path = pathof(pkg)
    return parse_syntax_recursive(file_path)
end

#####
##### Do stuff with the parsed files
#####

using JuliaSyntax
using JuliaSyntax: head
function count_interesting_things(tree::SyntaxNodeWrapper)
    counts = Dict{String, Int}()
    items = PostOrderDFS(tree)
    foreach(items) do wrapper
        k = kind(wrapper.node.raw)
        if k == K"="
            # 1-line function definitions like f() = abc...
            # Show up as an `=` with the first argument being a call
            # and the second argument being the function body.
            # We handle those here.
            # We do not handle anonymous functions like `f = () -> 1`
            kids = JuliaSyntax.children(wrapper.node)
            length(kids) == 2 || return
            kind(kids[1].raw) == K"call" || return
            key = "method"
            counts[key] = get(counts, key, 0) + 1
        elseif k == K"function"
            # This is a function like function f() 1+1 end
            key = "method"
            counts[key] = get(counts, key, 0) + 1
        elseif k == K"struct"
            # These we increment once
            key = string(k)
            counts[key] = get(counts, key, 0) + 1
        elseif k  == K"export"
            # These we count by the number of their children, since that's the number of exports/packages
            # being handled by that invocation of the keyword
            key = string(k)
            counts[key] = get(counts, key, 0) + length(JuliaSyntax.children(wrapper.node))
        end
    end
    return counts
end

function print_syntax_counts_summary(io::IO, counts, indent=0)
    total_count = item -> sum(row.count for row in counts if row.item == item; init=0)
    n_struct = total_count("struct")
    n_method = total_count("method")
    n_export = total_count("export")
    n = maximum(ndigits(x) for x in (n_struct, n_method, n_export))
    _print = (num, name) -> println(io, " "^indent, "* ", rpad(num, n), " ", name)
    _print(n_export, "exports")
    _print(n_struct, "struct definitions")
    _print(n_method, "method definitions")
    return nothing
end

#####
##### Entrypoint
#####

function analyze_syntax(arg)
    table = ParsedCountsEltype[]
    file_tree_pairs = parse_syntax_recursive(arg)
    for (file_name, tree) in file_tree_pairs
        file_counts = count_interesting_things(tree)
        for (item, count) in file_counts
            push!(table, (; file_name, item, count))
        end
    end
    return table
end
