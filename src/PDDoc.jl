export PDDoc,
       pdDocOpen,
       pdDocGetPageCount,
       pdDocGetPage

@compat abstract type PDDoc end

function pdDocOpen(fp::String)
  doc = PDDocImpl(fp)
  update_page_tree(doc)
  return doc
end

function pdDocGetPageCount(doc::PDDoc)
  return get_internal_pagecount(doc.pages)
end

function pdDocGetCatalog(doc::PDDoc)
  return doc.catalog
end

function pdDocGetPage(doc::PDDoc, num::Int)
  cosobj = find_page_from_treenode(doc.pages, num)
  return create_pdpage(doc, cosobj)
end

function pdDocGetPage(doc::PDDoc, name::String)
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
  doc.pages = cosDocGetObject(doc.cosDoc, pagesref)
  populate_doc_pages(doc, doc.pages)
end

function get_internal_pagecount(dict::CosObject)
  mytype = get(dict, PageTreeNode_Type)
  if (isequal(mytype, Catlog_PageTree_Root))
    return get(get(dict, PageTreeNode_Count))
  elseif (isequal(mytype, PageTreeNode_Page))
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
  mytype = get(node, PageTreeNode_Type)
  #If this is a page object the pageno has to be 1
  if isequal(mytype, PageTreeNode_Page)
    if pageno == 1
      return node
    else
      error(E_INVALID_OBJECT)
    end
  end

  kids = get(node, PageTreeNode_Kids)
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
