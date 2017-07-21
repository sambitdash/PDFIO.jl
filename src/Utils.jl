export get_tempdir,
       get_tempfilepath,
       util_open,
       util_close,
       OPEN_FILES
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

"""
Gets a temp file path and io to work on.
"""
MYCOUNTER=0
function get_tempfilepath()
  global MYCOUNTER
  MYCOUNTER+=1
  path=get_tempdir()*"/"*string(MYCOUNTER)
  #println(path)
  return (path,util_open(path,"w"))

  #return mktemp(get_tempdir())
end

OPEN_FILES=[]

function util_open(filename, mode)
  io=open(filename, mode)
  push!(OPEN_FILES, (filename,io))
  println(OPEN_FILES)
  return io
end

using BufferedStreams

import BufferedStreams: close

function util_close(inb::BufferedInputStream)
  close(inb)
end

function Base.close(stream::BufferedInputStream)

    if !isopen(stream)
        return
    end
    if applicable(close, stream.source)
      idx=1
      for file in OPEN_FILES
        if (stream.source === file[2])
          println(file[1])
          deleteat!(OPEN_FILES,idx)
          break
        end
        idx+=1
      end
      close(stream.source)
    end
    stream.position = 0
    empty!(stream.buffer)
    return
end

function util_close(handle)
  idx=1
  for file in OPEN_FILES
    if (handle === file[2])
      close(handle)
      deleteat!(OPEN_FILES,idx)
      return
    end
    idx+=1
  end
  error("IO handle not found")
end
