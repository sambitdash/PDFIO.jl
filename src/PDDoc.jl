export PDDoc,
       pdDocOpen,
       pdDocClose,
       pdDocGetCatalog,
       pdDocGetInfo, pdDocGetProducers,
       pdDocGetCosDoc,
       pdDocGetPageCount,
       pdDocGetPage

using ..Common

@compat abstract type PDDoc end

function pdDocOpen(fp::String)
  doc = PDDocImpl(fp)
  update_page_tree(doc)
  update_structure_tree(doc)
  return doc
end

function pdDocClose(doc::PDDoc)
  cosDocClose(doc.cosDoc)
end

function pdDocGetPageCount(doc::PDDoc)
  return get_internal_pagecount(doc.pages)
end

function pdDocGetCatalog(doc::PDDoc)
  return doc.catalog
end

pdDocGetCosDoc(doc::PDDoc)= doc.cosDoc

function pdDocGetPage(doc::PDDoc, num::Int)
  cosobj = find_page_from_treenode(doc.pages, num)
  return create_pdpage(doc, cosobj)
end

function pdDocGetPage(doc::PDDoc, name::String)
end

function pdDocGetInfo(doc::PDDoc)
    ref = get(doc.cosDoc.trailer[1], CosName("Info"))
    obj = cosDocGetObject(doc.cosDoc, ref)
    return obj
end

function pdDocGetProducers(doc::PDDoc)
    info = pdDocGetInfo(doc)
    creator = CDTextString(get(info, CosName("Creator")))
    producer = CDTextString(get(info, CosName("Producer")))
    return Dict("creator" => creator, "producer" => producer)
end

@compat mutable struct PDDocImpl <: PDDoc
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
  if (CosName("Pages") == get(dict, CosName("Type")))
    kids = get(dict, CosName("Kids"))
    arr = get(kids)
    len = length(arr)
    for i=1:len
      ref = splice!(arr,1)
      obj = cosDocGetObject(doc.cosDoc, ref)
      if (obj != CosNull)
        push!(arr, obj)
        populate_doc_pages(doc, obj)
      end
    end
  end
  parent = get(dict, CosName("Parent"))
  if !isequal(parent,CosNull)
    obj = cosDocGetObject(doc.cosDoc, parent)
    set!(dict,CosName("Parent"),obj)
  end
  return nothing
end

function update_page_tree(doc::PDDocImpl)
  pagesref = get(doc.catalog, CosName("Pages"))
  doc.pages = cosDocGetObject(doc.cosDoc, pagesref)
  populate_doc_pages(doc, doc.pages)
end

function get_internal_pagecount(dict::CosObject)
  mytype = get(dict, CosName("Type"))
  if (isequal(mytype, CosName("Pages")))
    return get(get(dict, CosName("Count")))
  elseif (isequal(mytype, CosName("Page")))
    return 1
  else
    error(E_INVALID_OBJECT)
  end
end

"""
This implementation may seem non-intuitive to some due to recursion and also
seemingly non-standard way of computing page count. However, PDF spec does not
discount the possibility of an intermediate node having page and pages nodes
in the kids array. Hence, this implementation.
"""
function find_page_from_treenode(node::CosObject, pageno::Int)
  mytype = get(node, CosName("Type"))
  #If this is a page object the pageno has to be 1
  if isequal(mytype, CosName("Page"))
    if pageno == 1
      return node
    else
      error(E_INVALID_OBJECT)
    end
  end

  kids = get(node, CosName("Kids"))
  kidsarr = get(kids)

  sum = 0
  for kid in kidsarr
    cnt = get_internal_pagecount(kid)
    if ((sum + cnt) >= pageno)
      return find_page_from_treenode(kid, pageno-sum)
    else
      sum += cnt
    end
  end
end

function update_structure_tree(doc::PDDocImpl)
  catalog = pdDocGetCatalog(doc)
  marking = get(catalog, CosName("MarkInfo"))

  if (marking !== CosNull)
    tagged = get(marking, CosName("Marked"))
    suspect = get(marking, CosName("Suspect"))
    doc.isTagged = (suspect === CosTrue) ? (:suspect) :
                   (tagged  === CosTrue) ? (:tagged)  : (:none)
  end
end
