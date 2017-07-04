using PDFIO
using PDFIO.PD
using PDFIO.Cos
using Base.Test


#pdDocOpen,
#pdDocGetPageCount,
#pdDocGetPage

#pdPageGetContent,
#pdPageIsEmpty

doc = pdDocOpen("files/1.pdf")

@test pdDocGetPageCount(doc) == 2

page = pdDocGetPage(doc, 1)

@test pdPageIsEmpty(page) == false

contents = pdPageGetContents(page)

bufstm = get(contents)
buf = read(bufstm)

@test length(buf) == 18669
