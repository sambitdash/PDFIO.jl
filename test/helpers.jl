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
