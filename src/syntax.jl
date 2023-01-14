#####
##### Connect AbstractTrees to JuliaSyntax
#####


# AbstractTrees.children(node::SyntaxNode) = JuliaSyntax.children(node)
AbstractTrees.children(node::JuliaSyntax.GreenNode) = JuliaSyntax.children(node)

export analyze_syntax
function analyze_syntax(pkg::Module)
    file = read(pathof(pkg), String)
    parsed = JuliaSyntax.parse(JuliaSyntax.SyntaxNode, file)
    tree = parsed[1]

end

function AbstractTrees.children(node::JuliaSyntax.SyntaxNode)
    k = kind(node.raw)
    if k in [K"function", K"struct", K"export", K"using", K"call"]
        return ()
    end
    return JuliaSyntax.children(node)

end
