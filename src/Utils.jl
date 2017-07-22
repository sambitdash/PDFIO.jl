export get_tempdir,
       get_tempfilepath,
       util_open,
       util_close,
       utilPrintOpenFiles

# Non-exported variable that retains the current tempdir location.
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

get_tempfilepath()=mktemp(get_tempdir())
util_open(filename, mode)=open(filename, mode)
util_close(handle::IOStream)=close(handle)
utilPrintOpenFiles()=[]
