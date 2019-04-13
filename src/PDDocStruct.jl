mutable struct StructTreeRoot
    k::CosObject                                    # Dict, Array or null
    idTree::Nullable{CosTreeNode{CDTextString}}     # Name tree
    parentTree::Nullable{CosTreeNode{Int}}          # Number tree
    parentTreeNext::Int
    roleMap::CosObject                              # Dict or null
    classMap::CosObject                             # Dict or null
end

mutable struct StructElem
    s::CosName
    p::CosObject                                    # Indirect Dict
    id::Vector{UInt8}
    pg::CosObject                                   # Dict
    k::Union{StructElem, CosObject}
    a::CosObject
    r::Int
    t::CDTextString
    lang::CDTextString
    alt::CDTextString
    e::CDTextString
    actualText::CDTextString
end

function get_structure_tree_root(obj::CosObject)
    @assert cn"StructTreeRoot" = get(obj, cn"Type")
    k = get(obj, cn"K")
    ptreeobj = get(obj, cn"ParentTree")
    idtreeobj = get(obj, cn"IDTree")
    prtNext = get(obj, cn"ParentTreeNextKey")
    parentTreeNext = (prtNext === CosNull) ? -1 : get(prtNext)

    parentTree = ptreeobj === CosNull ? Nullable{CosTreeNode{Int}}() :
                                        Nullable(createTreeNode(Int, ptreeobj))
    idTree    = idtreeobj === CosNull ? Nullable{CosTreeNode{String}}() :
                                        Nullable(createTreeNode(String, idtreeobj))
    roleMap  = get(obj, cn"RoleMap")
    classMap = get(obj, cn"ClassMap")

    return StructTreeRoot(k, idTree, parentTree, parentTreeNext, roleMap, classMap)
end

function get_structure_elem(obj::CosObject)
    @assert cn"StructElem" = get(obj, cn"Type")
    s = get(obj, cn"S")
    p = get(obj, cn"P")
    id = get(obj, cn"ID") |> get
    pg = get(obj, cn"Pg")
    k::Union{StructElem, CosObject}
    a = get(obj, cn"A")
    tobj = get(obj, cn"R")
    r = tobj === CosNull ? 0 : get(tobj)
    tobj = get(obj, cn"T")
    t = tobj === CosNull ? "" : convert(CDTextString, tobj)
    tobj = get(obj, cn"Lang")
    lang = tobj === CosNull ? "" : convert(CDTextString, tobj)
    tobj = get(obj, cn"Alt")
    alt = tobj === CosNull ? "" : convert(CDTextString, tobj)
    tobj = get(obj, cn"E")
    e = tobj === CosNull ? "" : convert(CDTextString, tobj)
    tobj = get(obj, cn"ActualText")
    actualText = tobj === CosNull ? "" : convert(CDTextString, tobj)

    return StructElem(s, p, id, pg, k, a, r, t, lang, alt, e, actualText)
end
