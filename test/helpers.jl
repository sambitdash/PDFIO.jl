#This has very limited methods created to use the PDFIO functionality for
#testing and quick prototyping. While you can use them to get some of the
#regular testing these are not currently part of the core library.

using PDFIO
using PDFIO.Common
using PDFIO.Cos
using PDFIO.PD

function pdfhlp_extract_doc_content_to_dir(filename,dir=tempdir())
  file=rsplit(filename, '/',limit=2)
  filenm=file[end]
  dirpath=joinpath(dir,filenm)
  if isdir(dirpath)
    rm(dirpath; force=true, recursive=true)
  end
  mkdir(dirpath)
  doc=pdDocOpen(filename)
  try
    npage= pdDocGetPageCount(doc)
    for i=1:npage
      page = pdDocGetPage(doc, i)
      if pdPageIsEmpty(page)==false
        contents=pdPageGetContents(page)
        bufstm = get(contents)
        buf = read(bufstm)
        close(bufstm)
        path=joinpath(dirpath,string(i)*".txt")
        write(path, buf)
      end
    end
  finally
    pdDocClose(doc)
  end
end

function pdfhlp_extract_doc_embedded_files(filename,dir=tempdir())
  file=rsplit(filename, '/',limit=2)
  filenm=file[end]
  dirpath=joinpath(dir,filenm)
  if isdir(dirpath)
    rm(dirpath; force=true, recursive=true)
  end
  mkdir(dirpath)
  doc=pdDocOpen(filename)
  try
    catalog = pdDocGetCatalog(doc)
    names = get(catalog, CosName("Names"))
    cosDoc = pdDocGetCosDoc(doc)
    nmdict = cosDocGetObject(cosDoc, names)
    println(nmdict)
    if nmdict !== CosNull
      efref  = get(nmdict, CosName("EmbeddedFiles"))
      efroot = cosDocGetObject(cosDoc, efref)
      #simple case no tree just a few files attached in the root node.
      #A proper implementation needs full names tree traversal.
      efarr = get(efroot, CosName("Names"))
      data = get(efarr)
      len=length(data)
      println(len)
      for i=1:len:2
        key=data[i]
        println(key)
        val=data[i+1]
        filespec=cosDocGetObject(cosDoc, val)
        ef=get(filespec, CosName("EF"))
        filename=get(filespec,CosName("F")) #UF could be there as well.
        stmref=get(ef, CosName("F"))
        stm=cosDocGetObject(cosDoc,stmref)
        bufstm=decode(stm)
        buf=read(bufstm)
        close(bufstm)
        path=joinpath(dirpath,get(filename))
        write(path,buf)
      end
    end
  finally
    pdDocClose(doc)
  end
end

function pdfhlp_extract_doc_attachment_files(filename,dir=tempdir())
  file=rsplit(filename, '/',limit=2)
  filenm=file[end]
  dirpath=joinpath(dir,filenm)
  if isdir(dirpath)
    rm(dirpath; force=true, recursive=true)
  end
  mkdir(dirpath)
  doc=pdDocOpen(filename)
  cosDoc=pdDocGetCosDoc(doc)
  try
    npage= pdDocGetPageCount(doc)
    for i=1:npage
      page = pdDocGetPage(doc, i)
      cospage = pdPageGetCosObject(page)
      annots=cosDocGetObject(cosDoc, get(cospage, CosName("Annots")))
      if (annots === CosNull)
        continue
      end
      annotsarr=get(annots)
      for annot in annotsarr
        annotdict = cosDocGetObject(cosDoc, annot)
        subtype = get(annotdict,CosName("Subtype"))
        if (subtype == CosName("FileAttachment"))
          filespec=cosDocGetObject(cosDoc, get(annotdict,CosName("FS")))
          ef=get(filespec, CosName("EF"))
          filename=get(filespec,CosName("F")) #UF could be there as well.
          stmref=get(ef, CosName("F"))
          stm=cosDocGetObject(cosDoc,stmref)
          bufstm=decode(stm)
          buf=read(bufstm)
          close(bufstm)
          path=joinpath(dirpath,get(filename))
          write(path,buf)
        end
      end
    end
  finally
    pdDocClose(doc)
  end
end
