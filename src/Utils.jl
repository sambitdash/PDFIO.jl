export get_tempdir,
       get_tempfilepath,
       util_open,
       util_close,
       utilPrintOpenFiles
# Non-exportable variable that retains the current tempdir location.
# This shoould be only accessed by get_tempdir() only

CURRENT_TMPDIR=""

"""
On every launch of the application a new directory needs to be created
that will have the path of the new directory.
"""
function get_tempdir()
    global CURRENT_TMPDIR
    if (CURRENT_TMPDIR == "" )||!isdir(CURRENT_TMPDIR)
        CURRENT_TMPDIR= abspath(mktempdir())
    end
    return CURRENT_TMPDIR
end


const DEBUG=false

if DEBUG
  MYCOUNTER=0
  OPEN_FILES=Vector{Tuple{AbstractString,IOStream}}()

  using BufferedStreams

  import Base: close

  function Base.close(stream::BufferedInputStream{IOStream})
    if !isopen(stream)
        return
    end
    util_close(stream.source)
    stream.position = 0
    empty!(stream.buffer)
    return
  end
end

"""
Gets a temp file path and io to work on.
"""
function get_tempfilepath(;debug=DEBUG)
  if debug
    global MYCOUNTER
    MYCOUNTER+=1
    path=get_tempdir()*"/"*string(MYCOUNTER)
    return (path,util_open(path,"w"))
  else
    return mktemp(get_tempdir())
  end
end

function util_open(filename, mode; debug=DEBUG)
  io=open(filename, mode)
  if debug
    push!(OPEN_FILES, (filename,io))
  end
  return io
end

function util_close(handle::IOStream; debug=DEBUG)
  if debug
    idx=1
    for file in OPEN_FILES
      if (handle === file[2])
        @printf("Closing open file: %s, %d\n", file[1],idx)
        close(handle)
        deleteat!(OPEN_FILES,idx)
        return
      end
      idx+=1
    end
    error("IO handle not found")
  else
    close(handle)
  end
end

function utilPrintOpenFiles(;debug=DEBUG)
  if debug
    println("The following files are opened currently:")
    println("-----------------------------------------")
    println(OPEN_FILES)
    println("-----------------------------------------")
  end
end
