#=
The file contains methods which can override file operations to ensure that
the files are closed properly. This needs to be included in the test case with
DEBUG=true. default is false.

This is kept external to the regular library to ensure normal library operations
are not affected.
=#
const DEBUG=false

@static if DEBUG

import PDFIO.Common: get_tempfilepath,
                     util_open, util_close, utilPrintOpenFiles

import Base: close

IODebug=[0, Vector{Tuple{AbstractString, IO}}()]

function get_tempfilepath()
    global IODebug
    IODebug[1] += 1
    path = joinpath(get_tempdir(), string(IODebug[1]))
    return (path, util_open(path, "w"))
end

function util_open(filename, mode)
    global IODebug
    io=open(filename, mode)
    println("Opening file: ", filename)
    push!(IODebug[2], (filename, io))
    return io
end

function util_close(handle::IOStream)
    global IODebug
    idx=1
    for file in IODebug[2]
        if (handle === file[2])
            println("Closing file: ", file[1], " ", idx)
            close(handle)
            deleteat!(IODebug[2],idx)
            return
        end
        idx+=1
    end
    error("IO handle not found")
end

util_close(handle::IOBuffer) = close(handle)

function utilPrintOpenFiles()
    global IODebug
    println("The following files are opened currently:")
    println("-----------------------------------------")
    for f in IODebug[2]
        println(f)
    end
    println("-----------------------------------------")
    return IODebug[2]
end

end

function files_equal(f1, f2)
    io1 = util_open(f1, "r"); io2 = util_open(f2, "r")
    buf1 = read(io1); buf2 = read(io2)
    util_close(io1); util_close(io2)
    return buf1 == buf2
end

function extract_text(io, doc)
    npage = pdDocGetPageCount(doc)
    for i=1:npage
        page = pdDocGetPage(doc, i)
        if pdPageIsEmpty(page) == false
            pdPageGetContentObjects(page)
            pdPageExtractText(io, page)
            println(io)
        end
    end
end
