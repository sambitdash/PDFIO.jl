using PDFIO
using PDFIO.PD
using PDFIO.Cos
using Base.Test

#This file is part of the test folder

println("Test FlateDecode")
doc = pdDocOpen("files/1.pdf")
@test pdDocGetPageCount(doc) == 2
page = pdDocGetPage(doc, 1)
@test pdPageIsEmpty(page) == false
contents = pdPageGetContents(page)
bufstm = get(contents)
buf = read(bufstm)
@test length(buf) == 18669

#This file is part of the test folder

println("PDF File with ObjectStreams")
doc = pdDocOpen("files/pdf-17.pdf")
@test pdDocGetPageCount(doc) == 1
page = pdDocGetPage(doc, 1)
@test pdPageIsEmpty(page) == false
contents = pdPageGetContents(page)
bufstm = get(contents)
buf = read(bufstm)
@test length(buf) == 1021

#This file is to be downloaded from the test database

println("General File Opening 3")

download("http://www.stillhq.com/pdfdb/000003/data.pdf", "3.pdf")
doc = pdDocOpen("3.pdf")
@test pdDocGetPageCount(doc) == 30
page = pdDocGetPage(doc, 1)
@test pdPageIsEmpty(page) == false

#This file is to be downloaded from the test database

println("Test RunLengthDecode")
download("http://www.stillhq.com/pdfdb/000582/data.pdf", "582.pdf")
doc = pdDocOpen("582.pdf")
@test pdDocGetPageCount(doc) == 12
obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc, PDFIO.Cos.CosIndirectObjectRef(177, 0))
stm=get(obj)
data=read(stm)
@test length(data)==273


#This file is to be downloaded from the test database

println("Test ASCIIHexDecode")
download("http://www.stillhq.com/pdfdb/000325/data.pdf", "325.pdf")
doc = pdDocOpen("325.pdf")
@test pdDocGetPageCount(doc) == 1
obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc, PDFIO.Cos.CosIndirectObjectRef(7, 0))
stm=get(obj)
data=read(stm)
@test length(data)==121203


println("Test ASCII85Decode")
download("http://www.stillhq.com/pdfdb/000388/data.pdf", "388.pdf")
doc = pdDocOpen("388.pdf")
@test pdDocGetPageCount(doc) == 1
obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc, PDFIO.Cos.CosIndirectObjectRef(9, 0))
stm=get(obj)
data=read(stm)
@test length(data)==38118
