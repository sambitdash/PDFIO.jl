using Test
using PDFIO
using PDFIO.PD
using PDFIO.Cos
using PDFIO.Common
using ZipFile
using AbstractTrees

# Internal methods for testing only
using PDFIO.Cos: parse_indirect_ref, decode_ascii85, CosXString, parse_value
using PDFIO.PD: openssl_error
using PDFIO.Common: read_pkcs12

include("debugIO.jl")

pdftest_ver  = "0.0.7"
pdftest_link = "https://github.com/sambitdash/PDFTest/archive/v"*pdftest_ver

zipfile = "pdftest-"*pdftest_ver
pdftest_link *= ".zip"
zipfile *= ".zip"
pdftest_dir="PDFTest-"*pdftest_ver*"/"

if !isdir(pdftest_dir)
    isfile(zipfile) || download(pdftest_link, zipfile)
    r = ZipFile.Reader(zipfile)
    buf = Vector{UInt8}(undef, 64*1024)
    for f in r.files
        println("Filename: $(f.name)")
        if f.method == ZipFile.Store
            isdir(f.name) || mkdir(f.name)
        elseif f.method == ZipFile.Deflate
            isfile(f.name) ||
                write(f.name, read(f, Vector{UInt8}(undef, f.uncompressedsize)))
        end
    end
    close(r)
end

for (root, dirs, files) in walkdir(joinpath(@__DIR__, pdftest_dir, "fonts"))
    dest = joinpath(@__DIR__, "..", "data", "fonts")
    for file in files
        isfile(joinpath(dest, file)) && continue
        println("Copying $file to $dest")
        cp(joinpath(root, file), joinpath(dest, file), force=true)
    end
end

function testfiles(filename)
    name, ext = splitext(filename)
    return (name*".res", joinpath(@__DIR__, pdftest_dir, "templates", name*".txt"))
end

function local_testfiles(filename, filesdir="files")
    name, ext = splitext(filename)
    return (name*".res", joinpath(@__DIR__, pdftest_dir, "templates", name*".txt"),
            joinpath(@__DIR__, pdftest_dir, filesdir, filename))
end

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
        @test CDRect(CosArray(CosObject[
                               CosInt(0),
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
        @test CDDate("D:20090202010202+00'01") < CDDate("D:20090202010202") <
            CDDate("D:20090202010203") < CDDate("D:20090202010203-00'01")
        @test CDDate("D:20090202-01'01") > CDDate("D:20090202-00'01") >
            CDDate("D:20090202+00'01") > CDDate("D:20090202+01'01")
        @test isless(CDDate("D:2009020208+06"), CDDate("D:2009020204+01"))
        @test isequal(CDDate("D:2009020208+06"), CDDate("D:2009020204+02"))
        @test getUTCTime(CDDate("D:20190425173659+05'30")) ==
            CDDate("D:20190425120659Z")
    end
    @testset "Crypto APIs" begin
        @test_throws ErrorException openssl_error(0)
        @test openssl_error(1) === nothing
        cacerts   = joinpath(@__DIR__, "..", "data", "certs", "cacerts.pem")
        @testset "Self-sign certs" begin
            files = ["sample01.pdf", "sample02.pdf", "sample03.pdf", "sample04.pdf",
                     "sample05.pdf", "sample06.pdf", "sample07.pdf", "sample08.pdf"]
            isfile(cacerts) && rm(cacerts)
            doc = pdDocOpen(joinpath(@__DIR__, pdftest_dir, "DigSig", "sample01.pdf"))
            @test pdDocHasSignature(doc)
            r = pdDocValidateSignatures(doc, export_certs=true)
            pdDocClose(doc)
            @test r[1][:passed] == false
            @test isfile("sample01.pem")
            cp("sample01.pem", cacerts, force=true)
            for file in files
                doc = pdDocOpen(joinpath(@__DIR__, pdftest_dir, "DigSig", file))
                @test pdDocHasSignature(doc)
                r = pdDocValidateSignatures(doc)
                @test all([r[i][:passed] for i = 1:length(r)])
                pdDocClose(doc)
            end
        end
        @testset "Expired Certs" begin
            files = ["pdf-signer-tool-guide.pdf", "samplecertifiedpdf.pdf"]
            for file in files
                isfile(cacerts) && rm(cacerts)
                doc = pdDocOpen(joinpath(@__DIR__, pdftest_dir, "DigSig", file))
                @test pdDocHasSignature(doc)
                r = pdDocValidateSignatures(doc)
                @test all([r[i][:passed] for i = 1:length(r)])
                pdDocClose(doc)
            end
        end
        @testset "PDF 2.0 experimental" begin
            files = ["pades_example-1.pdf", "PAdES_SmartID.pdf",
                     "sbid_3rd_party_sign_pades.pdf", "sbid_authbased_signflow_pades.pdf"]
            for file in files
                isfile(cacerts) && rm(cacerts)
                doc = pdDocOpen(joinpath(@__DIR__, pdftest_dir, "DigSig", file))
                @test pdDocHasSignature(doc)
                r = pdDocValidateSignatures(doc)
                @test all([r[i][:passed] for i = 1:length(r)])
                pdDocClose(doc)
            end
        end

        @testset "PDF user password documents" begin
            files = ["dt-256-aes.pdf",              # V-5 R-6 supported in PDF 2.0
                     "dt-embed-protected.pdf",      # V-2 R-3
                     "dt-own-pass-same.pdf",        # V-2 R-3 - upw = opw = user
                     "dt.pdf",                      # V-2 R-3
                     "dt-protected.pdf",            # V-4 R-4
                     "dt-nopass.pdf",               # No encryption
                     "pdf-example-password.pdf",    # V-2 R-3
                     "pdf-example-encryption.pdf",  # V-2 R-3 No user password
                     "upw-password-opw-sample.pdf", # V-5 R-5
                     "samplesecured_256bitaes.pdf", # V-5 R-5
                     ]           
            pws = Vector{UInt8}[b"user", b"user", b"user", b"user", b"user", b"", b"test", b"", b"password", b""]
            infos = []
            encrypted = []
            for i = 1:length(files)
                file = files[i]
                resname, template, filename = local_testfiles(file)
                doc = pdDocOpen(joinpath(@__DIR__, pdftest_dir, "encrypt", file), access=()->Base.SecretBuffer!(pws[i]))
                page = pdDocGetPage(doc, 1)
                push!(infos, pdDocGetInfo(doc))
                open(resname, "w") do io
                    pdPageExtractText(io, page)
                end
                push!(encrypted, cosDocIsEncrypted(doc.cosDoc))
                if i != 9
                    @test files_equal(resname, template)
                else
                    @test stat(resname).size == 0
                end
                pdDocClose(doc)
            end
            @test infos[1]["Producer"] == "SAMBox 1.1.57 (www.sejda.org)"
            @test infos[2]["Producer"] == "LibreOffice 6.0"
            @test infos[3]["Producer"] == "LibreOffice 6.0"
            @test infos[4]["Producer"] == "LibreOffice 6.0"
            @test infos[5]["Producer"] =="3-Heights(TM) PDF Security Shell 4.8.25.2 (http://www.pdf-tools.com)"
            @test infos[6]["Producer"] == "LibreOffice 6.0"
            @test all(encrypted[1:5])
        end
        @testset "PDF owner password documents" begin
            files = ["dt.pdf", "dt-own-pass-same.pdf", "upw-password-opw-sample.pdf"]
            opws = Vector{UInt8}[b"owner", b"user", b"sample"]
            for i = 1:length(files)
                file = files[i]
                resname, template, filename = local_testfiles(file)
                doc = pdDocOpen(joinpath(@__DIR__, pdftest_dir, "encrypt", file), access=()->Base.SecretBuffer!(opws[i]))
                page = pdDocGetPage(doc, 1)
                open(resname, "w") do io
                    pdPageExtractText(io, page)
                end
                if i != 3
                    @test files_equal(resname, template)
                else
                    @test stat(resname).size == 0
                end
                @test doc.cosDoc.secHandler.keys[cn"StdCF"][1] == 0xffffffff
                pdDocClose(doc)
            end
        end
        @testset "PDF Crypt filter" begin
            files = ["dt-att-protected.pdf"]
            opws = Vector{UInt8}[b"user1234"]
            for i = 1:length(files)
                file = files[i]
                doc = pdDocOpen(joinpath(@__DIR__, pdftest_dir, "encrypt", file), access=()->Base.SecretBuffer!(opws[i]))
                obj = cosDocGetObject(doc.cosDoc, CosIndirectObjectRef(43, 0))
                @test String(read(get(obj))) == "An embedded text file. "
                pdDocClose(doc)
            end
        end
        @testset "PKI Security Handlers" begin
            files = ["dt-embed-protected-cert.pdf",
                     "dt-all-aes-128.pdf",
                     "dt-cert-all.pdf",
                     "dt-rc-4-all.pdf"
                     ]
            infos = []
            encrypted = []
            pw = Base.SecretBuffer("password")
            p12path = joinpath(@__DIR__, pdftest_dir, "certs", "doc-crypt.p12")
            Base.shred!(pw) do pw
                for i = 1:length(files)
                    file = files[i]
                    resname, template, filename = local_testfiles(file)
                    path = joinpath(@__DIR__, pdftest_dir, "encrypt", file)
                    doc = pdDocOpen(path, access=()->read_pkcs12(p12path, pw))
                    page = pdDocGetPage(doc, 1)
                    push!(infos, pdDocGetInfo(doc))
                    open(resname, "w") do io
                        pdPageExtractText(io, page)
                    end
                    push!(encrypted, cosDocIsEncrypted(doc.cosDoc))
                    @test files_equal(resname, template)
                    pdDocClose(doc)
                end
            end
            @test infos[1]["Producer"] == "LibreOffice 6.0"
            @test infos[2]["Producer"] == "LibreOffice 6.0"
            @test infos[3]["Producer"] == "LibreOffice 6.0"
            @test infos[4]["Producer"] == "LibreOffice 6.0"
            @test all(encrypted)
        end
    end
    
    @testset "Test FlateDecode" begin
        @test begin
            resname, template, filename = local_testfiles("1.pdf")
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
            resname, template, filename = local_testfiles("1_noinfo.pdf")
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
            resname, template, filename = local_testfiles("empty_property.pdf")
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

    @testset "PDF File with ObjectStreams" begin
        @test begin
            resname, template, filename = local_testfiles("pdf-17.pdf")
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
            filename=pdftest_dir*"stillhq/3.pdf"
            DEBUG && println(filename)
            @assert isfile(filename)
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
            @test files_equal(resfile, template)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Floating point CIDWidth" begin
        @test begin
            filename="sample-google-doc.pdf"
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
            @test files_equal(resfile, template)
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
            @test files_equal(resfile, template)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Corrupt File" begin
        @test begin
            resfile, template, filename = local_testfiles("A1947-14.pdf")
            DEBUG && println(filename)
            doc = pdDocOpen(filename)
            try
                npage= pdDocGetPageCount(doc)
                for i=1:npage
                    page = pdDocGetPage(doc, i)
                    @assert i == pdPageGetPageNumber(page)
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
            filename=pdftest_dir*"stillhq/582.pdf"
            DEBUG && println(filename)
            @assert isfile(filename)
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
            filename=pdftest_dir*"stillhq/325.pdf"
            DEBUG && println(filename)
            @assert isfile(filename)
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
            filename=pdftest_dir*"stillhq/388.pdf"
            DEBUG && println(filename)
            @assert isfile(filename)
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
            filename=pdftest_dir*"stillhq/589.pdf"
            DEBUG && println(filename)
            @assert isfile(filename)
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
            filename=pdftest_dir*"stillhq/339.pdf"
            DEBUG && println(filename)
            @assert isfile(filename)
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
            filename=pdftest_dir*"stillhq/504.pdf"
            DEBUG && println(filename)
            @assert isfile(filename)
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
            DEBUG && PDFIO.Cos.parse_data(pdftest_dir*"files/page5.txt")
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Page label test with outlines" begin
        @test begin
            resfile, template, filename = local_testfiles("431.pdf", "stillhq")
            DEBUG && println(filename)
            @assert isfile(filename) 
            doc = pdDocOpen(filename)
            @assert pdDocGetPageCount(doc) == 54
            @assert pdDocHasPageLabels(doc)
            @assert pdDocGetPageLabel(doc, 3) == "ii"
            @assert pdDocGetPageLabel(doc,  1) == "title"
            @assert pdDocGetPageLabel(doc,  3) == "ii"
            @assert pdDocGetPageLabel(doc, 46) == "42"
            @assert PDFIO.Cos.cosDocGetPageNumbers(doc.cosDoc, doc.catalog, "title") == range(1, length=1)
            @assert PDFIO.Cos.cosDocGetPageNumbers(doc.cosDoc, doc.catalog, "ii") == range(3, length=1)
            @assert PDFIO.Cos.cosDocGetPageNumbers(doc.cosDoc, doc.catalog, "42") == range(46, length=1)
            pdDocGetPageRange(doc, "iii")
            outline = pdDocGetOutline(doc)
            iobuf = IOBuffer()
            print_tree(iobuf, outline)
            write("431.toc.res", take!(iobuf))
            @assert files_equal("431.toc.res", pdftest_dir*"templates/431.toc")
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
        resfile, template, filename = local_testfiles("1.pdf")
        doc = pdDocOpen(filename)
        @test pdDocHasPageLabels(doc) == false
        @test_throws ErrorException(E_INVALID_PAGE_LABEL) pdDocGetPageRange(doc, "1")
        pdDocClose(doc)
    end

    @testset "Outlines" begin
        @test begin
            resfile, template, filename = local_testfiles("outline.pdf")
            DEBUG && println(filename)
            @assert isfile(filename) 
            doc = pdDocOpen(filename)
            outline = pdDocGetOutline(doc)
            iobuf = IOBuffer()
            print_tree(iobuf, outline)
            write("outline.toc.res", take!(iobuf))
            @assert files_equal("outline.toc.res", pdftest_dir*"templates/outline.toc")
            @assert pdOutlineItemGetAttr(outline[1][1][1][1])[:Destination][2].pageno == 5
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Symbol Fonts test" begin
        @test begin
            filename="431.pdf"
            result, template_file = local_testfiles(filename)
            DEBUG && println(filename)
            @assert isfile(pdftest_dir*"stillhq/"*filename)
            doc = pdDocOpen(pdftest_dir*"stillhq/"*filename)
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
            resname, template, filename = local_testfiles("pdf-sample.pdf")
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
                @test files_equal(result, template_file)
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
                @test files_equal(result, template_file)
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

for (root, dirs, files) in walkdir(joinpath(@__DIR__, pdftest_dir, "fonts"))
    dest = joinpath(@__DIR__, "..", "data", "fonts")
    for file in files
        println("Removing $file from $dest")
        isfile(joinpath(dest, file)) && rm(joinpath(dest, file))
    end
end

if isfile("pvt/pvttests.jl")
    include("pvt/pvttests.jl")
end
