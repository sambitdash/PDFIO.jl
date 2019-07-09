using ..Cos
import Base: get
using ..Cos: CosDocImpl

mutable struct PDDocImpl <: PDDoc
    cosDoc::CosDocImpl
    catalog::CosIndirectObject{CosDict}
    pages::IDDN{CosDict}
    structTreeRoot::IDDN{CosDict}
    isTagged::Symbol #Valid values :tagged, :none and :suspect
    fonts::Dict{CosObject, PDFont}
    xobjs::Dict{CosObject, PDXObject}
    pager2n::Dict{CosIndirectObjectRef, Int}
    pagen2r::Dict{Int, CosIndirectObjectRef}
    function PDDocImpl(fp::AbstractString; access::Function)
        cosDoc = cosDocOpen(fp, access=access)
        catalog = cosDocGetRoot(cosDoc)
        new(cosDoc,catalog,CosNull,CosNull,:none,
            Dict{CosObject, PDFont}(), Dict{CosObject, PDXObject}(),
            Dict{CosIndirectObjectRef, Int}(),
            Dict{Int, CosIndirectObjectRef}())
    end
end

pdDocGetPage(doc::PDDocImpl, num::Int) = 
    pdDocGetPage(doc, pd_doc_get_page(doc, num))

pdDocGetPage(doc::PDDoc, cosref::CosIndirectObjectRef) = 
    create_pdpage(doc, cosDocGetObject(doc.cosDoc, cosref))

#=
```
    show(io::IO, doc::PDDoc)
```
Prints the PDDoc. The intent is to print lesser information from the structure.
=#
function Base.show(io::IO, doc::PDDoc)
    print(io, "\nPDDoc ==>\n")
    print(io, doc.cosDoc)
    print(io, '\n')
    print(io, "Catalog:")
    print(io, doc.catalog)
    print(io, "isTagged: $(doc.isTagged)\n")
end

#=
Recursively reads the page object and populates the indirect objects
Ensures indirect objects are read and updated in the xref Dictionary.
=#
function populate_doc_pages(doc::PDDocImpl, dict::CosIndirectObject{CosDict},
                            ncurr::Int)
    if (cn"Pages" == cosDocGetObject(doc.cosDoc, dict, cn"Type"))
        kids = cosDocGetObject(doc.cosDoc, dict, cn"Kids")
        arr = get(kids)
        len = length(arr)
        for i=1:len
            ref = splice!(arr, 1)
            obj = cosDocGetObject(doc.cosDoc, ref)
            if obj !== CosNull
                push!(arr, obj)
                ncurr = populate_doc_pages(doc, obj, ncurr)
            end
        end
    else
        ncurr += 1
        ref = CosIndirectObjectRef(dict)
        doc.pager2n[ref]   = ncurr
        doc.pagen2r[ncurr] = ref
    end
    parent = cosDocGetObject(doc.cosDoc, dict, cn"Parent")
    if (parent === CosNull)
        obj = cosDocGetObject(doc.cosDoc, parent)
        set!(dict, cn"Parent", obj)
    end
    return ncurr
end

populate_doc_pages(doc::PDDocImpl, dict::CosNullType, ncurr::Int) = nothing

pd_doc_get_pagenum(doc, pagenum::Int) = pagenum
pd_doc_get_pagenum(doc, pageref::CosIndirectObjectRef) = doc.pager2n[pageref]
pd_doc_get_page(doc, pagenum::Int) = doc.pagen2r[pagenum]

@inline function update_page_tree(doc::PDDocImpl)
    pages = cosDocGetObject(doc.cosDoc, doc.catalog, cn"Pages")
    populate_doc_pages(doc, pages, 0)
    doc.pages = pages
    return nothing
end

# The structure tree is not fully loaded but the object linkages are established for future
# correlations during text extraction.

@inline function update_structure_tree!(doc::PDDocImpl)
    catalog = pdDocGetCatalog(doc)
    marking = cosDocGetObject(doc.cosDoc, catalog, cn"MarkInfo")

    if (marking !== CosNull)
        tagged  = cosDocGetObject(doc.cosDoc, marking, cn"Marked")
        suspect = cosDocGetObject(doc.cosDoc, marking, cn"Suspect")
        doc.isTagged = (suspect === CosTrue) ? (:suspect) :
                       (tagged  === CosTrue) ? (:tagged)  : (:none)
    end

    doc.structTreeRoot = cosDocGetObject(doc.cosDoc, catalog, cn"StructTreeRoot")
    return nothing
end

function get_pd_font!(doc::PDDocImpl, cosfont::IDD{CosDict})
    font = get(doc.fonts, cosfont, nothing)
    font !== nothing && return font
    font = doc.fonts[cosfont] = PDFont(doc, cosfont)
    return font
end

function get_pd_xobject!(doc::PDDocImpl, cosxobj::CosObject)
    xobj = get(doc.xobjs, cosxobj, nothing)
    xobj !== nothing && return xobj
    xobj = doc.xobjs[cosxobj] = createPDXObject(doc, cosxobj)
    return xobj
end

function gather_sig_props(doc, fld, inherit)
    inhdown = Dict{Symbol, Any}()
    if cosDocGetObject(doc.cosDoc, fld, cn"FT") === cn"Sig"
        tobj = cosDocGetObject(doc.cosDoc, fld, cn"T")
        # Better to collect the page reference
        p_ref = cosDocGetObject(doc.cosDoc, fld, cn"P")
        page = p_ref === CosNull ? get(inherit, :P, CosNull) : p_ref
        tparent = get(inherit, :FQT, "")
        t = tobj !== CosNull ? CDTextString(tobj) : ""
        fqt = !isempty(tparent) && !isempty(t) ? tparent*"."*t :
            !isempty(tparent) ? tparent :
            !isempty(t) ? t : ""
        !isempty(fqt)    && (inhdown[:FQT] = fqt)
        page !== CosNull && (inhdown[:P]   = page)
    end
    return inhdown
end

function pd_get_signature_fields!(doc::PDDocImpl, fldroot::IDD{CosArray},
                                  inherit, sigflds)
    fldarr = get(fldroot)
    for fldobj in fldarr
        fld  = cosDocGetObject(doc.cosDoc, fldobj)
        inhdown = gather_sig_props(doc, fld, inherit)
        cosDocGetObject(doc.cosDoc, fld, cn"FT") === cn"Sig" &&
            push!(sigflds, (fld, inhdown))
        kids = cosDocGetObject(doc.cosDoc, fld, cn"Kids")
        kids !== CosNull && 
            pd_get_signature_fields!(doc, kids, inhdown, sigflds)
    end
end

