#####
##### Connect AbstractTrees to JuliaSyntax
#####


AbstractTrees.children(node::JuliaSyntax.SyntaxNode) = JuliaSyntax.children(node)
AbstractTrees.children(node::SyntaxNode) = JuliaSyntax.children(node)
AbstractTrees.children(node::JuliaSyntax.GreenNode) = JuliaSyntax.children(node)

export analyze_syntax
function analyze_syntax(pkg::Module)

    file = read(pathof(pkg), String)
    parsed = JuliaSyntax.parse(SyntaxNode, file)
    tree = parsed[1]
end
