using PDFIO
using PDFIO.PD
using PDFIO.Cos
using PDFIO.Common
using Base.Test


@testset "PDFIO tests" begin

  @testset "Test FlateDecode" begin
    @test begin
      filename="files/1.pdf"
      println(filename)
      doc = pdDocOpen(filename)
      @assert pdDocGetPageCount(doc) == 2
      page = pdDocGetPage(doc, 1)
      @assert pdPageIsEmpty(page) == false
      contents = pdPageGetContents(page)
      bufstm = get(contents)
      buf = read(bufstm)
      close(bufstm)
      @assert length(buf) == 18669
      @assert length(pdPageGetContentObjects(page).objs)==190
      pdDocClose(doc)
      utilPrintOpenFiles()
      files=readdir(get_tempdir())
      length(files)==0
    end
  end

  @testset "PDF File with ObjectStreams" begin
    @test begin
      filename="files/pdf-17.pdf"
      println(filename)
      doc = pdDocOpen(filename)
      @assert pdDocGetPageCount(doc) == 1
      page = pdDocGetPage(doc, 1)
      @assert pdPageIsEmpty(page) == false
      contents = pdPageGetContents(page)
      bufstm = get(contents)
      buf = read(bufstm)
      close(bufstm)
      @assert length(buf) == 1021
      @assert length(pdPageGetContentObjects(page).objs)==1
      pdDocClose(doc)
      utilPrintOpenFiles()
      files=readdir(get_tempdir())
      length(files)==0
    end
  end

  @testset "General File Opening 3" begin
    @test begin
      filename="3.pdf"
      println(filename)
      isfile(filename)||
        download("http://www.stillhq.com/pdfdb/000003/data.pdf",filename)
      doc = pdDocOpen(filename)
      @assert pdDocGetPageCount(doc) == 30
      page = pdDocGetPage(doc, 1)
      @assert pdPageIsEmpty(page) == false
      pdDocClose(doc)
      utilPrintOpenFiles()
      files=readdir(get_tempdir())
      length(files)==0
    end
  end

  @testset "Test RunLengthDecode" begin
    @test begin
      filename="582.pdf"
      println(filename)
      isfile(filename)||
        download("http://www.stillhq.com/pdfdb/000582/data.pdf",filename)
      doc = pdDocOpen(filename)
      @assert pdDocGetPageCount(doc) == 12
      obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc,
        PDFIO.Cos.CosIndirectObjectRef(177, 0))
      stm=get(obj)
      data=read(stm)
      close(stm)
      @assert length(data)==273
      pdDocClose(doc)
      utilPrintOpenFiles()
      files=readdir(get_tempdir())
      length(files)==0
    end
  end

  @testset "Test ASCIIHexDecode" begin
    @test begin
      filename="325.pdf"
      println(filename)
      isfile(filename)||
        download("http://www.stillhq.com/pdfdb/000325/data.pdf",filename)
      doc = pdDocOpen(filename)
      @assert pdDocGetPageCount(doc) == 1
      obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc,
        PDFIO.Cos.CosIndirectObjectRef(7, 0))
      stm=get(obj)
      data=read(stm)
      close(stm)
      @assert length(data)==121203
      pdDocClose(doc)
      utilPrintOpenFiles()
      files=readdir(get_tempdir())
      length(files)==0
    end
  end

  @testset "Test ASCII85Decode" begin
    @test begin
      filename="388.pdf"
      println(filename)
      isfile(filename)||
        download("http://www.stillhq.com/pdfdb/000388/data.pdf",filename)
      doc = pdDocOpen(filename)
      @assert pdDocGetPageCount(doc) == 1
      obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc,
        PDFIO.Cos.CosIndirectObjectRef(9, 0))
      stm=get(obj)
      data=read(stm)
      close(stm)
      @assert length(data)==38118
      pdDocClose(doc)
      utilPrintOpenFiles()
      files=readdir(get_tempdir())
      length(files)==0
    end
  end

  @testset "Test read_string" begin
    @test begin
      PDFIO.Cos.parse_data("files/page5.txt")
      utilPrintOpenFiles()
      true
    end
  end
end
