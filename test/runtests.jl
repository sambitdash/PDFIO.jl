using PDFIO
using PDFIO.PD
using PDFIO.Cos
using PDFIO.Common
using Base.Test

include("debugIO.jl")

@testset "PDFIO tests" begin

  @testset "Test FlateDecode" begin
    @test begin
      filename="files/1.pdf"
      println(filename)
      doc = pdDocOpen(filename)
      println(pdDocGetCatalog(doc))
      cosDoc = pdDocGetCosDoc(doc)
      map(println, cosDoc.trailer)
      info = pdDocGetInfo(doc)
      @assert info["Producer"] == "LibreOffice 5.3" && info["Creator"] == "Writer"
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
      length(utilPrintOpenFiles())==0
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
      length(utilPrintOpenFiles())==0
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
      length(utilPrintOpenFiles())==0
    end
  end

  @testset "Hybrid x-ref" begin
    @test begin
      filename="A1947-14.pdf"
      println(filename)
      isfile(filename)||
        download("http://lawmin.nic.in/ld/P-ACT/1947/A1947-14.pdf",filename)
      doc = pdDocOpen(filename)
      try
        npage= pdDocGetPageCount(doc)
        for i=1:npage
          page = pdDocGetPage(doc, i)
          if pdPageIsEmpty(page)==false
            pdPageGetContentObjects(page)
          end
        end
      finally
        pdDocClose(doc)
      end
      length(utilPrintOpenFiles())==0
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
      length(utilPrintOpenFiles())==0
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
      length(utilPrintOpenFiles())==0
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
      length(utilPrintOpenFiles())==0
    end
  end

  @testset "Test read_string" begin
    @test begin
      PDFIO.Cos.parse_data("files/page5.txt")
      length(utilPrintOpenFiles())==0
    end
  end
  files=readdir(get_tempdir())
  @assert length(files)==0
end

if isfile("pvt/pvttests.jl")
  #include("pvt/pvttests.jl")
end
