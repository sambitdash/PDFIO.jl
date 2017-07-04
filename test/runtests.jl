using PDFIO
using PDFIO.PD
using PDFIO.Cos
using Base.Test

#This file is part of the test folder

doc = pdDocOpen("files/1.pdf")

@test pdDocGetPageCount(doc) == 2

page = pdDocGetPage(doc, 1)

@test pdPageIsEmpty(page) == false

contents = pdPageGetContents(page)

bufstm = get(contents)
buf = read(bufstm)

@test length(buf) == 18669

#This file is part of the test folder

doc = pdDocOpen("files/pdf-17.pdf")

@test pdDocGetPageCount(doc) == 1

page = pdDocGetPage(doc, 1)

@test pdPageIsEmpty(page) == false

contents = pdPageGetContents(page)

bufstm = get(contents)
buf = read(bufstm)

@test length(buf) == 1021

#This file is to be downloaded from the test database

download("http://www.stillhq.com/pdfdb/000003/data.pdf", "files/3.pdf")

doc = pdDocOpen("files/3.pdf")

@test pdDocGetPageCount(doc) == 30

page = pdDocGetPage(doc, 1)

@test pdPageIsEmpty(page) == false
