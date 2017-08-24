mutable struct PDDocImpl <: PDDoc
    cosDoc::CosDoc
    catalog::CosObject
    pages::CosObject
    isTagged::Symbol #Valid values :tagged, :none and :suspect
    function PDDocImpl(fp::String)
        cosDoc = cosDocOpen(fp)
        catalog = cosDocGetRoot(cosDoc)
        new(cosDoc,catalog,CosNull,:none)
    end
end

"""
Recursively reads the page object and populates the indirect objects
Ensures indirect objects are read and updated in the xref Dictionary.
"""
function populate_doc_pages(doc::PDDocImpl, dict::CosObject)
    if (cn"Pages" == get(dict, cn"Type"))
        kids = get(dict, cn"Kids")
        arr = get(kids)
        len = length(arr)
        for i=1:len
            ref = splice!(arr,1)
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

function update_page_tree(doc::PDDocImpl)
    pagesref = get(doc.catalog, cn"Pages")
    doc.pages = cosDocGetObject(doc.cosDoc, pagesref)
    populate_doc_pages(doc, doc.pages)
end

#=
This implementation may seem non-intuitive to some due to recursion and also
seemingly non-standard way of computing page count. However, PDF spec does not
discount the possibility of an intermediate node having page and pages nodes
in the kids array. Hence, this implementation.
=#
function find_page_from_treenode(node::CosObject, pageno::Int)
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
        (sum + cnt) >= pageno && return find_page_from_treenode(kid, pageno-sum)
        sum += cnt
    end
    throw(ErrorException(E_INVALID_PAGE_NUMBER))
end

function update_structure_tree(doc::PDDocImpl)
    catalog = pdDocGetCatalog(doc)
    marking = get(catalog, cn"MarkInfo")

    if (marking !== CosNull)
        tagged = get(marking, cn"Marked")
        suspect = get(marking, cn"Suspect")
        doc.isTagged = (suspect === CosTrue) ? (:suspect) :
                       (tagged  === CosTrue) ? (:tagged)  : (:none)
    end
    return nothing
end
