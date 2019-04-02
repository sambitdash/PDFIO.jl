using ..Cos
import Base: get
using ..Cos: CosDocImpl

mutable struct PDDocImpl <: PDDoc
    cosDoc::CosDocImpl
    catalog::CosIndirectObject{CosDict}
    pages::IDDN{CosDict}
    structTreeRoot::CosObject
    isTagged::Symbol #Valid values :tagged, :none and :suspect
    fonts::Dict{CosObject, PDFont}
    xobjs::Dict{CosObject, PDXObject}
    function PDDocImpl(fp::AbstractString)
        cosDoc = cosDocOpen(fp)
        catalog = cosDocGetRoot(cosDoc)
        new(cosDoc,catalog,CosNull,CosNull,:none,
            Dict{CosObject, PDFont}(), Dict{CosObject, PDXObject}())
    end
end

function pdDocGetPage(doc::PDDocImpl, num::Int)
    cosobj = find_page_from_treenode(doc.pages, num)
    return create_pdpage(doc, cosobj)
end

"""
```
    show(io::IO, doc::PDDoc)
```
Prints the PDDoc. The intent is to print lesser information from the structure.
"""
function Base.show(io::IO, doc::PDDoc)
    print(io, "\nPDDoc ==>\n")
    print(io, doc.cosDoc)
    print(io, '\n')
    print(io, "Catalog:")
    print(io, doc.catalog)
    print(io, "isTagged: $(doc.isTagged)\n")
end

"""
Recursively reads the page object and populates the indirect objects
Ensures indirect objects are read and updated in the xref Dictionary.
"""
populate_doc_pages(doc::PDDocImpl, dict::CosIndirectObject{CosDict}) =
    populate_doc_pages(doc, dict.obj)

function populate_doc_pages(doc::PDDocImpl, dict::CosDict)
    if (cn"Pages" == get(dict, cn"Type"))
        kids = cosDocGetObject(doc.cosDoc, dict, cn"Kids")
        arr = get(kids)
        len = length(arr)
        for i=1:len
            ref = splice!(arr, 1)
            obj = cosDocGetObject(doc.cosDoc, ref)
            if obj !== CosNull
                push!(arr, obj)
                populate_doc_pages(doc, obj)
            end
        end
    end
    parent = get(dict, cn"Parent")
    if (parent === CosNull)
        obj = cosDocGetObject(doc.cosDoc, parent)
        set!(dict,CosName("Parent"),obj)
    end
    return nothing
end

populate_doc_pages(doc::PDDocImpl, dict::CosObject) = nothing

function update_page_tree(doc::PDDocImpl)
    pagesref = get(doc.catalog, cn"Pages")::CosIndirectObjectRef
    pages = cosDocGetObject(doc.cosDoc, pagesref)::CosIndirectObject{CosDict}
    populate_doc_pages(doc, pages)
    doc.pages = pages
    return nothing
end

#=
This implementation may seem non-intuitive to some due to recursion and also
seemingly non-standard way of computing page count. However, PDF spec does not
discount the possibility of an intermediate node having page and pages nodes
in the kids array. Hence, this implementation.
=#
function find_page_from_treenode(node::IDD{CosDict}, pageno::Int)
    mytype = get(node, cn"Type")
    #If this is a page object the pageno has to be 1
    if mytype == cn"Page"
        pageno == 1 && return node
        throw(ErrorException(E_INVALID_PAGE_NUMBER))
    end
    kids = get(node, cn"Kids")
    kidsarr = get(kids)
    sum = 0
    for kid in kidsarr
        cnt = Cos.get_internal_pagecount(kid)
        (sum + cnt) >= pageno &&
            return find_page_from_treenode(kid, pageno-sum)
        sum += cnt
    end
    throw(ErrorException(E_INVALID_PAGE_NUMBER))
end

# The structure tree is not fully loaded but the object linkages are established for future
# correlations during text extraction.

function update_structure_tree!(doc::PDDocImpl)
    catalog = pdDocGetCatalog(doc)
    marking = get(catalog, cn"MarkInfo")

    if (marking !== CosNull)
        tagged = get(marking, cn"Marked")
        suspect = get(marking, cn"Suspect")
        doc.isTagged = (suspect === CosTrue) ? (:suspect) :
                       (tagged  === CosTrue) ? (:tagged)  : (:none)
    end

    structTreeRef = get(catalog, cn"StructTreeRoot")
    doc.structTreeRoot = cosDocGetObject(doc.cosDoc, structTreeRef)
    return nothing
end

get_pd_font!(doc::PDDocImpl, cosfont::IDD{CosDict}) =
    get!(doc.fonts, cosfont, PDFont(doc, cosfont))

get_pd_xobject!(doc::PDDocImpl, cosxobj::CosObject) = 
    get!(doc.xobjs, cosxobj, createPDXObject(doc, cosxobj))

