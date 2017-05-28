export get_tempdir,
       get_tempfilepath
# Non-exportable variable that retains the current tempdir location.
# This shoould be only accessed by get_tempdir() only

CURRENT_TMPDIR=""

"""
On every launch of the application a new directory needs to be created
that will have the path of the new directory.
"""
function get_tempdir()
    global CURRENT_TMPDIR
    if (CURRENT_TMPDIR == "" )
        CURRENT_TMPDIR= abspath(mktempdir())
    end
    return CURRENT_TMPDIR
end

"""
Gets a temp file path and io to work on.
"""
function get_tempfilepath()
    return mktemp(get_tempdir())
end
