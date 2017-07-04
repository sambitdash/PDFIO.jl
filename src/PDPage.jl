export PDPage,
       pdPageGetContents,
       pdPageIsEmpty

@compat abstract type PDPage end

type PDPageImpl <: PDPage
  doc::PDDocImpl
  cospage::CosObject
  contents::CosObject
end

function pdPageGetContents(page::PDPageImpl)
  if (page.contents === CosNull)
    ref = get_page_content_ref(page)
    page.contents = get_page_contents(page, ref)
  end
  return page.contents
end

function pdPageIsEmpty(page::PDPageImpl)
  return page.contents === CosNull && get_page_content_ref(page) === CosNull
end

PDPageImpl(doc::PDDocImpl, cospage::CosObject) = PDPageImpl(doc, cospage,CosNull)

#=This function is added as non-exported type. PDPage may need other attributes
which will make the constructor complex. This is the default will all default
values.
=#
function create_pdpage(doc::PDDocImpl, cospage::CosObject)
  return PDPageImpl(doc, cospage)
end

#=
This will return a CosArray of ref or ref to a stream. This needs to be converted
to an actual stream object
=#
function get_page_content_ref(page::PDPageImpl)
  return get(page.cospage, CosName("Contents"))
end

function get_page_contents(page::PDPageImpl, contents::CosArray)
  len = length(contents)
  for i = 1:len
    ref = splice!(contents, 1)
    cosstm = get_page_contents(page.doc.cosDoc,ref)
    if (cosstm != CosNull)
      push!(contents,cosstm)
    end
  end
  return contents
end

function get_page_contents(page::PDPageImpl, contents::CosIndirectObjectRef)
  return cosDocGetObject(page.doc.cosDoc, contents)
end

function get_page_contents(page::PDPage, contents::CosObject)
  return CosNull
end
