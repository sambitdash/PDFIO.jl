export PDDoc,
       pdDocOpen,
       pdDocGetPageCount

abstract PDDoc

function pdDocOpen(fp::String)
  doc = PDDocImpl(fp)
  update_page_tree(doc)
  return doc
end

const PageTreeNode_Count=CosName("Count")
const PageTreeNode_Type =CosName("Type")
const PageTreeNode_Kids =CosName("Kids")
const PageTreeNode_Parent=CosName("Parent")

const Catlog_PageTree_Root = CosName("Pages")


function pdDocGetPageCount(doc::PDDoc)
  return get(pages, PageTreeNode_Count)
end

function pdDocGetCatalog(doc::PDDoc)
  return doc.catalog
end

type PDDocImpl <: PDDoc
  cosDoc::CosDoc
  catalog::CosObject
  pages::CosObject
  function PDDocImpl(fp::String)
    cosDoc = cosDocOpen(fp)
    catalog = cosDocGetRoot(cosDoc)
    new(cosDoc,catalog,CosNull)
  end
end

type PageTreeNode
  parent::CosObject
  kids::CosArray
  count::Int
  PageTreeNode()=new(CosNull, [], 0)
end

"""
Recursively reads the page object and populates the indirect objects
Ensures indirect objects are read and updated in the xref Dictionary.
"""
function populate_doc_pages(doc::PDDocImpl, dict::CosObject)
  if (isequal(Catlog_PageTree_Root,get(dict, PageTreeNode_Type)))
    #print(dict)
    kids = get(dict, PageTreeNode_Kids)
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
  parent = get(dict, PageTreeNode_Parent)
  if !isequal(parent,CosNull)
    obj = cosDocGetObject(doc.cosDoc, parent)
    set!(dict,PageTreeNode_Parent,obj)
  end
  return nothing
end

function update_page_tree(doc::PDDocImpl)
  pagesref = get(doc.catalog, Catlog_PageTree_Root)
  print(pagesref)
  doc.pages = cosDocGetObject(doc.cosDoc, pagesref)
  populate_doc_pages(doc, doc.pages)
end
