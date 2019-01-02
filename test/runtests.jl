using Test
using PDFIO
using PDFIO.PD
using PDFIO.Cos
using PDFIO.Common

# Internal methods for testing only
using PDFIO.Cos: parse_indirect_ref, decode_ascii85, CosXString, parse_value

include("debugIO.jl")

@testset "PDFIO tests" begin
    @testset "Miscellaneous" begin
        @test_throws ErrorException skipv(IOBuffer([UInt8(65), UInt8(66)]),
                                          UInt8(66))
        @test CDTextString(CosXString([UInt8('0'), UInt8('0'),
                                       UInt8('4'),UInt8('1')]))=="A"
        @test CDTextString(CosXString([UInt8('4'), UInt8('2'),
                                       UInt8('4'),UInt8('1')]))=="BA"
        @test CosFloat(CosInt(1)) == CosFloat(1f0)
        @test [CosFloat(1f0), CosInt(2)] == [CosFloat(1f0), CosFloat(2f0)]
        @test CDRect(CosArray([CosInt(0),
                               CosInt(0),
                               CosInt(640),
                               CosInt(480)])) == CDRect(0, 0, 640, 480)
        @test parse_indirect_ref(IOBuffer(b"10 0 R\n")) ==
            CosIndirectObjectRef(10, 0)
        @test string(parse_value(IOBuffer("% This is a comment\r\n"))) ==
                     "% This is a comment"
    end

    @testset "CDDate" begin
        @test string(CDDate("D:199812231952-08'30 "))==
            "D:19981223195200-08'30"
        @test_throws ErrorException CDDate("not a date")
        @test_throws ErrorException CDDate("D:209")
        @test CDDate("D:2009") == CDDate("D:20090101000000Z")
        @test CDDate("D:200902") == CDDate("D:20090201000000+00")
        @test CDDate("D:20090202") == CDDate("D:20090202000000-00")
        @test CDDate("D:2009020201") == CDDate("D:20090202010000+00'00")
        @test CDDate("D:200902020102") == CDDate("D:20090202010200+00'00")
        @test CDDate("D:20090202010203") == CDDate("D:20090202010203+00'00")
        @test CDDate("D:20090202010203-00'01") < CDDate("D:20090202010202") < CDDate("D:20090202010203") < CDDate("D:20090202010203+00'01")
        @test CDDate("D:20090202+01'01") > CDDate("D:20090202+00'01") > CDDate("D:20090202-00'01") > CDDate("D:20090202-01'01")
        @test isless(CDDate("D:2009020208-06"), CDDate("D:2009020204-01"))
        @test isequal(CDDate("D:2009020208-06"), CDDate("D:2009020204-02"))
    end

    @testset "Test FlateDecode" begin
        @test begin
            filename="files/1.pdf"
            DEBUG && println(filename)
            doc = pdDocOpen(filename)
            DEBUG && println(pdDocGetCatalog(doc))
            cosDoc = pdDocGetCosDoc(doc)
            DEBUG && map(println, cosDoc.trailer)
            info = pdDocGetInfo(doc)
            @assert info["Producer"] == "LibreOffice 5.3" && info["Creator"] == "Writer"
            @assert pdDocGetPageCount(doc) == 2
            page = pdDocGetPage(doc, 1)
            @assert pdPageGetMediaBox(page) == pdPageGetCropBox(page)
            @assert pdPageIsEmpty(page) == false
            contents = pdPageGetContents(page)
            bufstm = get(contents)
            buf = read(bufstm)
            close(bufstm)
            @assert length(buf) == 18669
            @assert length(pdPageGetContentObjects(page).objs)==190
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end
    @testset "Document without Info" begin
        @test begin
            filename="files/1_noinfo.pdf"
            DEBUG && println(filename)
            doc = pdDocOpen(filename)
            DEBUG && println(pdDocGetCatalog(doc))
            cosDoc = pdDocGetCosDoc(doc)
            DEBUG && map(println, cosDoc.trailer)
            info = pdDocGetInfo(doc)
            @assert info === nothing
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Document with empty property" begin
        @test begin
            filename="files/empty_property.pdf"
            DEBUG && println(filename)
            doc = pdDocOpen(filename)
            DEBUG && println(pdDocGetCatalog(doc))
            cosDoc = pdDocGetCosDoc(doc)
            DEBUG && map(println, cosDoc.trailer)
            info = pdDocGetInfo(doc)
            @assert info == Dict(
                "Producer" => "Scribus PDF Library 1.3.3.13",
                "CreationDate" => CDDate("D:20090807192622"),
                "ModDate" => CDDate("D:20090807192622"),
                "Creator" => "Scribus 1.3.3.13",
                "Trapped" => cn"False")
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Outlines" begin
        @test begin
            # This file has label catalog and usees /Dest outline entry (12.3.3 Document Outline)
            filename="431.pdf"
            DEBUG && println(filename)
            isfile(filename) ||
                download("http://www.stillhq.com/pdfdb/000431/data.pdf",filename)
            doc = pdDocOpen(filename)
            outline = pdDocGetOutline(doc)
            @assert outline !== nothing
            @assert length(outline) >= 20
            @assert outline[1][:Title] == "Table of Contents"
            @assert string(outline[1][:PageLabel]) == "i"
            @assert string(outline[1][:PageRef]) == "449 0 R"
            @assert outline[1][:PageNo] == 2
            @assert item_level(outline[1]) == 1
            @assert string(outline[19:20]) == """
11. Advanced Topics - Linux Boot Process | PageLabel=>28 | PageRef=>509 0 R | PageNo=>32 | Expanded=>false
  11.1. References for Boot Process | PageLabel=>30 | PageRef=>513 0 R | PageNo=>34
"""
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
        # This file created by LaTeX usees /A outline entry (12.3.3 Document Outline)
        filename="files/outline.pdf"
        DEBUG && println(filename)
        doc = pdDocOpen(filename)
        @test begin
            outline = pdDocGetOutline(doc, add_index = true)
            @assert outline !== nothing
            @assert string(outline[1:2]) == """
[1]: Chapter AA! | PageLabel=>2 | PageRef=>102 0 R | PageNo=>4 | Expanded=>false
[2][1]: Section AA.aa! | PageLabel=>3 | PageRef=>106 0 R | PageNo=>5 | Expanded=>false
[2][2][1]: SubSection AA.aa.a! | PageLabel=>3 | PageRef=>106 0 R | PageNo=>5 | Expanded=>false
[2][2][2][1]: SubSubSection AA.aa.a.a! | PageLabel=>3 | PageRef=>106 0 R | PageNo=>5 | Expanded=>false
[2][2][2][2][1]: Paragraph AA.aa.a.a.a! | PageLabel=>3 | PageRef=>106 0 R | PageNo=>5 | Expanded=>false
[2][2][2][2][2][1]: SubParagraph AA.aa.a.a.a.a! | PageLabel=>3 | PageRef=>106 0 R | PageNo=>5
[2][3]: Section AA.bb! | PageLabel=>3 | PageRef=>106 0 R | PageNo=>5 | Expanded=>false
[2][4][1]: SubSection AA.bb.a! | PageLabel=>3 | PageRef=>106 0 R | PageNo=>5 | Expanded=>false
[2][4][2][1]: SubSubSection AA.bb.a.a! | PageLabel=>4 | PageRef=>110 0 R | PageNo=>6 | Expanded=>false
[2][4][2][2][1]: Paragraph AA.bb.a.a.a! | PageLabel=>4 | PageRef=>110 0 R | PageNo=>6 | Expanded=>false
[2][4][2][2][2][1]: SubParagraph AA.bb.a.a.a.a! | PageLabel=>4 | PageRef=>110 0 R | PageNo=>6
[2][4][2][2][3]: Paragraph AA.bb.a.a.b! | PageLabel=>4 | PageRef=>110 0 R | PageNo=>6 | Expanded=>false
[2][4][2][2][4][1]: SubParagraph AA.bb.a.a.b.a! | PageLabel=>4 | PageRef=>110 0 R | PageNo=>6
[2][4][2][2][5]: Paragraph AA.bb.a.a.c! | PageLabel=>4 | PageRef=>110 0 R | PageNo=>6 | Expanded=>false
[2][4][2][2][6][1]: SubParagraph AA.bb.a.a.c.a! | PageLabel=>4 | PageRef=>110 0 R | PageNo=>6
[2][4][2][2][6][2]: SubParagraph AA.bb.a.a.c.b! | PageLabel=>4 | PageRef=>110 0 R | PageNo=>6
"""
            @assert items_count(outline[1:2]) == 16

            # Test iterator
            @assert items_count(outline) == length(items(outline)) == 18
            item = PDOutlineItem()
            for oi in items(outline)
                item = oi
                occursin("AA.bb.a.a.a!", oi[:Title]) && break
            end
            @assert string(item) == "Paragraph AA.bb.a.a.a! | PageLabel=>4 | PageRef=>110 0 R | Index=>(2, 4, 2, 2, 1) | PageNo=>6 | Expanded=>false"
            @assert item === outline[2][4][2][2][1]
            @assert item_level(item) == 5

            # Test if PageNo, PageLabel and PageRef refers to the same page
            item_pg = pdDocGetPage(doc, item[:PageNo])
            item_obj = pdPageGetCosObject(item_pg)
            @assert cosDocGetObject(pdDocGetCosDoc(doc), item[:PageRef]) == item_obj
            @assert item_obj in map(p->pdPageGetCosObject(p), pdDocGetPageRange(doc, string(item[:PageLabel])))

            # Test if PageNo is the right page
            buf = IOBuffer()
            pdPageExtractText(buf, item_pg)
            item_text = String(take!(buf))
            @assert occursin(item[:Title], item_text)
            true
        end
        @test begin
            outline = pdDocGetOutline(doc, depth = 1)
            @assert outline !== nothing
            @assert string(outline) == """
Chapter AA! | PageLabel=>2 | PageRef=>102 0 R | PageNo=>4 | Expanded=>false
  Section AA.aa! | PageLabel=>3 | PageRef=>106 0 R | PageNo=>5 | Expanded=>false
  Section AA.bb! | PageLabel=>3 | PageRef=>106 0 R | PageNo=>5 | Expanded=>false
Chapter BB! | PageLabel=>5 | PageRef=>114 0 R | PageNo=>7 | Expanded=>false
  Section BB.aa! | PageLabel=>5 | PageRef=>114 0 R | PageNo=>7
"""
            @assert items_count(outline) == 5
            @assert items_count(outline, depth = 1) - items_count(outline, depth = 0) == 3
            @assert items_count(outline[1]) == 1
            @assert items_count(outline[1:2]) == 3
            true
        end
        @test begin
            outline = pdDocGetOutline(doc, compact = true)
            @assert outline !== nothing
            @assert string(outline) == """
Chapter AA!
  Section AA.aa!
    SubSection AA.aa.a!
      SubSubSection AA.aa.a.a!
        Paragraph AA.aa.a.a.a!
          SubParagraph AA.aa.a.a.a.a!
  Section AA.bb!
    SubSection AA.bb.a!
      SubSubSection AA.bb.a.a!
        Paragraph AA.bb.a.a.a!
          SubParagraph AA.bb.a.a.a.a!
        Paragraph AA.bb.a.a.b!
          SubParagraph AA.bb.a.a.b.a!
        Paragraph AA.bb.a.a.c!
          SubParagraph AA.bb.a.a.c.a!
          SubParagraph AA.bb.a.a.c.b!
Chapter BB!
  Section BB.aa!
"""
            item = outline[2][2][1]
            @assert item[:Title] == "SubSection AA.aa.a!"
            @assert item_level(item) == 3
            @assert item ∈ items(outline, depth = 2)
            @assert item ∉ items(outline, depth = 1)
            true
        end
        pdDocClose(doc)
        length(utilPrintOpenFiles()) == 0
    end

    @testset "PDF File with ObjectStreams" begin
        @test begin
            filename="files/pdf-17.pdf"
            DEBUG && println(filename)
            doc = pdDocOpen(filename)
            @assert pdDocGetPageCount(doc) == 1
            page = pdDocGetPage(doc, 1)
            rm = pdPageGetMediaBox(page)
            rc = pdPageGetCropBox(page)
            @assert rm == CDRect(0, 0, 612, 792)
            @assert rc == CDRect(0, 0, 612, 792)
            @assert pdPageIsEmpty(page) == false
            contents = pdPageGetContents(page)
            bufstm = get(contents)
            buf = read(bufstm)
            close(bufstm)
            @assert length(buf) == 1021
            @assert length(pdPageGetContentObjects(page).objs)==1
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "General File Opening 3" begin
        @test begin
            filename="3.pdf"
            DEBUG && println(filename)
            isfile(filename)||
                download("http://www.stillhq.com/pdfdb/000003/data.pdf",filename)
            doc = pdDocOpen(filename)
            @assert pdDocGetPageCount(doc) == 30
            page = pdDocGetPage(doc, 1)
            @assert pdPageIsEmpty(page) == false
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Hybrid x-ref" begin
        @test begin
            filename="A1947-15.pdf"
            DEBUG && println(filename)
            resfile, template, filename = local_testfiles(filename)
            doc = pdDocOpen(filename)
            io = util_open(resfile, "w")
            try
                extract_text(io, doc)
            finally
                util_close(io)
                pdDocClose(doc)
            end
            @assert files_equal(resfile, template)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Non-standard CMap" begin
        @test begin
            filename="16-969_o7jp.pdf"
            DEBUG && println(filename)
            resfile, template, filename = local_testfiles(filename)
            doc = pdDocOpen(filename)
            io = util_open(resfile, "w")
            try
                extract_text(io, doc)
            finally
                util_close(io)
                pdDocClose(doc)
            end
            @assert files_equal(resfile, template)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Corrupt File" begin
        @test begin
            filename="files/A1947-14.pdf"
            DEBUG && println(filename)
            doc = pdDocOpen(filename)
            try
                npage= pdDocGetPageCount(doc)
                for i=1:npage
                    page = pdDocGetPage(doc, i)
                    if pdPageIsEmpty(page) == false
                        pdPageGetContentObjects(page)
                        pdPageExtractText(IOBuffer(), page)
                    end
                end
            finally
                pdDocClose(doc)
            end
            length(utilPrintOpenFiles()) == 0
        end
    end


    @testset "Test RunLengthDecode" begin
        @test begin
            filename="582.pdf"
            DEBUG && println(filename)
            isfile(filename)||
                download("http://www.stillhq.com/pdfdb/000582/data.pdf",filename)
            doc = pdDocOpen(filename)
            info = pdDocGetInfo(doc)
            @assert info["Trapped"] == cn"False"
            @assert pdDocGetPageCount(doc) == 12
            obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc,
                                          PDFIO.Cos.CosIndirectObjectRef(177, 0))
            stm=get(obj)
            data=read(stm)
            close(stm)
            @assert length(data) == 273
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Test ASCIIHexDecode" begin
        @test begin
        filename="325.pdf"
        DEBUG && println(filename)
        isfile(filename)||
            download("http://www.stillhq.com/pdfdb/000325/data.pdf",filename)
        doc = pdDocOpen(filename)
        @assert pdDocGetPageCount(doc) == 1
        obj = cosDocGetObject(doc.cosDoc, CosIndirectObjectRef(7, 0))
        stm=get(obj)
        data=read(stm)
        close(stm)
        @assert length(data) == 121203
        pdDocClose(doc)
        length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Test ASCII85Decode" begin
        @test take!(decode_ascii85(IOBuffer("zzz!!!~>"))) == fill(0x0, 14)
        @test begin
        filename="388.pdf"
        DEBUG && println(filename)
        isfile(filename)||
            download("http://www.stillhq.com/pdfdb/000388/data.pdf",filename)
        doc = pdDocOpen(filename)
        @assert pdDocGetPageCount(doc) == 1
        obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc, PDFIO.Cos.CosIndirectObjectRef(9, 0))
        stm=get(obj)
        data=read(stm)
        close(stm)
        @assert length(data) == 38117
        pdDocClose(doc)
        length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "LZWDecode Filter" begin
        @test begin
            filename="589.pdf"
            DEBUG && println(filename)
            isfile(filename)||
                download("http://www.stillhq.com/pdfdb/000589/data.pdf",filename)
            doc = pdDocOpen(filename)
            obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc, PDFIO.Cos.CosIndirectObjectRef(70, 0))
            stm=get(obj)
            data=read(stm)
            close(stm)
            @assert length(data) == 768
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
        @test begin
            filename="339.pdf"
            DEBUG && println(filename)
            isfile(filename)||
                download("http://www.stillhq.com/pdfdb/000339/data.pdf",filename)
            doc = pdDocOpen(filename)
            stm = get(cosDocGetObject(doc.cosDoc, CosIndirectObjectRef(4, 0)))
            buf = read(stm)
            util_close(stm)
            @assert length(buf) == 6636
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Content Array" begin
        @test begin
            filename="504.pdf"
            DEBUG && println(filename)
            isfile(filename)||
                download("http://www.stillhq.com/pdfdb/000504/data.pdf",filename)
            doc = pdDocOpen(filename)
            page = pdDocGetPage(doc, 1)
            contents = pdPageGetContents(page)
            stm = get(contents)
            buf = read(stm)
            util_close(stm)
            @assert length(buf) == 5574
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Test read_string" begin
        @test begin
            DEBUG && PDFIO.Cos.parse_data("files/page5.txt")
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Page label test" begin
        @test begin
            filename="431.pdf"
            DEBUG && println(filename)
            isfile(filename) ||
                download("http://www.stillhq.com/pdfdb/000431/data.pdf",filename)
            doc = pdDocOpen(filename)
            @assert pdDocGetPageCount(doc) == 54
            @assert pdDocHasPageLabels(doc)
            @assert PDFIO.Cos.cosDocGetPageNumbers(doc.cosDoc, doc.catalog, "title") ==
                range(1, length=1)
            @assert PDFIO.Cos.cosDocGetPageNumbers(doc.cosDoc, doc.catalog, "ii") ==
                range(3, length=1)
            @assert PDFIO.Cos.cosDocGetPageNumbers(doc.cosDoc, doc.catalog, "42") ==
                range(46, length=1)
            pdDocGetPageRange(doc, "iii")
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
        doc = pdDocOpen("files/1.pdf")
        @test pdDocHasPageLabels(doc) == false
        @test_throws ErrorException(E_INVALID_PAGE_LABEL) pdDocGetPageRange(doc, "1")
        pdDocClose(doc)
    end

    @testset "Symbol Fonts test" begin
        @test begin
            filename="431.pdf"
            result, template_file = local_testfiles(filename)
            DEBUG && println(filename)
            isfile(filename) ||
                download("http://www.stillhq.com/pdfdb/000431/data.pdf",filename)
            doc = pdDocOpen(filename)
            (npage = pdDocGetPageCount(doc)) == 54
            try
                open(result, "w") do io
                    for i=1:npage
                        page = pdDocGetPage(doc, i)
                        if pdPageIsEmpty(page) == false
                            pdPageGetContentObjects(page)
                            pdPageExtractText(io, page)
                        end
                    end
                end
                @assert files_equal(result, template_file)
            finally
                pdDocClose(doc)
            end
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Font Flags test" begin
        @test begin
            filename="files/pdf-sample.pdf"
            doc = pdDocOpen(filename)
            (npage = pdDocGetPageCount(doc)) == 1
            page = pdDocGetPage(doc, 1)
            fonts = pdPageGetFonts(page)
            d = Dict{CosName, Tuple}()
            for (k, v) in fonts
                d[k] = (pdFontIsAllCap(v), pdFontIsBold(v),
                        pdFontIsFixedW(v), pdFontIsItalic(v),
                        pdFontIsSmallCap(v))
            end
            @assert d[cn"F2"]  == (false, false, false, false, false)
            @assert d[cn"TT2"] == (false, true,  false, false, false)
            @assert d[cn"TT8"] == (false, true,  false, true,  false)
            @assert d[cn"TT6"] == (false, false, false, false, false)
            @assert d[cn"TT4"] == (false, false, false, false, false)
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Forms XObjects Test" begin
        @test begin
            filename="Graphics-wpf.pdf"
            result, template_file = testfiles(filename)
            DEBUG && println(filename)
            isfile(filename) ||
                download("http://www.pdfsharp.net/wiki/GetFile.aspx?"*
                         "File=%2fGraphics-sample%2fGraphics-wpf.pdf",
                         filename)
            doc = pdDocOpen(filename)
            @assert (npage = pdDocGetPageCount(doc)) == 5
            try
                open(result, "w") do io
                    for i=npage:npage
                        page = pdDocGetPage(doc, i)
                        if pdPageIsEmpty(page) == false
                            pdPageGetContentObjects(page)
                            pdPageExtractText(io, page)
                        end
                    end
                end
                @assert files_equal(result, template_file)
            finally
                 pdDocClose(doc)
            end
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Inline Image test" begin
        @test begin
            filename="Pratham-Sanskaran.pdf"
            result, template_file, src = local_testfiles(filename)
            DEBUG && println(src)
            doc = pdDocOpen(src)
            (npage = pdDocGetPageCount(doc)) == 3
            try
                open(result, "w") do io
                    for i=1:npage
                        page = pdDocGetPage(doc, i)
                        if pdPageIsEmpty(page) == false
                            pdPageGetContentObjects(page)
                            pdPageExtractText(io, page)
                        end
                    end
                end
                @assert files_equal(result, template_file)
            finally
                 pdDocClose(doc)
            end
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "MacRomanEncoding Fonts test" begin
        @test begin
            filename="spec-2.pdf"
            result, template_file, src = local_testfiles(filename)
            DEBUG && println(src)
            doc = pdDocOpen(src)
            @assert (npage = pdDocGetPageCount(doc)) == 1
            try
                open(result, "w") do io
                    for i=1:npage
                        page = pdDocGetPage(doc, i)
                        if pdPageIsEmpty(page) == false
                            pdPageGetContentObjects(page)
                            pdPageExtractText(io, page)
                        end
                    end
                end
                @assert files_equal(result, template_file)
            finally
                pdDocClose(doc)
            end
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Text before header test" begin
        @test begin
            filename="spec-2c.pdf"
            result, template_file, src = local_testfiles(filename)
            DEBUG && println(src)
            doc = pdDocOpen(src)
            @assert (npage = pdDocGetPageCount(doc)) == 1
            try
                open(result, "w") do io
                    for i=1:npage
                        page = pdDocGetPage(doc, i)
                        if pdPageIsEmpty(page) == false
                            pdPageGetContentObjects(page)
                            pdPageExtractText(io, page)
                        end
                    end
                end
                @assert files_equal(result, template_file)
            finally
                pdDocClose(doc)
            end
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Attachment PDF" begin
        filename = "fileAttachment.pdf"
        result, template_file, src = local_testfiles(filename)
        DEBUG && println(src)
        doc = pdDocOpen(src)
        val = string(pdDocGetNamesDict(doc))
        @test val == "\n33 0 obj\n<<\n\t/EmbeddedFiles\t34 0 R\n\t/JavaScript\t35 0 R\n>>\nendobj\n\n" ||
            val == "\n33 0 obj\n<<\n\t/JavaScript\t35 0 R\n\t/EmbeddedFiles\t34 0 R\n>>\nendobj\n\n"
        pdDocClose(doc)
        @test length(utilPrintOpenFiles()) == 0
    end
    files=readdir(get_tempdir())
    @assert length(files) == 0
end

if isfile("pvt/pvttests.jl")
    include("pvt/pvttests.jl")
end
