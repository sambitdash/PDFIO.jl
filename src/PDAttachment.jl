export PDAttachment,
       pdDocGetAttachments,
       pdAttachmentGetName,
       pdAttachmentGetData,
       pdAttachmentExtract,
       pdDocExtractAttachments

using ..Common, ..Cos

"""
```
    PDAttachment
```
A file embedded inside a PDF document. It's either listed in the document level
`EmbeddedFiles` name tree or attached to a page with a `FileAttachment`
annotation.

See [`pdDocGetAttachments`](@ref).
"""
struct PDAttachment
    name::String
    stream::CosObject
end

show(io::IO, att::PDAttachment) = print(io, "PDAttachment(", repr(att.name), ")")

"""
```
    pdAttachmentGetName(att::PDAttachment) -> String
```
Returns the file name of the attachment as recorded in the PDF document. The
name is not sanitized. It should not be used as a path without care. See
[`pdAttachmentExtract`](@ref).
"""
pdAttachmentGetName(att::PDAttachment) = att.name

"""
```
    pdAttachmentGetData(att::PDAttachment) -> Vector{UInt8}
```
Reads and decodes the contents of the attachment.
"""
function pdAttachmentGetData(att::PDAttachment)
    bufstm = get(att.stream)
    try
        return read(bufstm)
    finally
        util_close(bufstm)
    end
end

# Attachment file names are not trusted. Only a plain file name is retained.
function sanitize_filename(name::AbstractString)
    name = String(last(split(replace(name, '\\' => '/'), '/')))
    name = replace(name, r"[\x00-\x1f\x7f-\x9f<>:\"|?*]" => "_")
    name = String(rstrip(strip(name), ['.', ' ']))
    # Windows device names are unusable as file names, even with an extension.
    occursin(r"^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\..*)?$"i, name) &&
        (name = "_" * name)
    return name in ("", ".", "..") ? "attachment" : name
end

# Creates a new file in `dir`. `O_EXCL` makes the creation atomic, so an existing
# file or a symbolic link is never opened. A numeric suffix is tried instead.
function create_new_file(dir::AbstractString, name::String)
    base, ext = splitext(name)
    for i = 0:typemax(Int16)
        path = joinpath(dir, i == 0 ? name : string(base, " (", i, ")", ext))
        # On Windows `O_EXCL` still follows a dangling symbolic link. This check
        # does not cover a link created between it and the `open`.
        islink(path) && continue
        try
            flags = Base.Filesystem.JL_O_WRONLY | Base.Filesystem.JL_O_CREAT |
                    Base.Filesystem.JL_O_EXCL
            # 0o666 is subject to the umask of the user, like a regular `write`.
            return path, Base.Filesystem.open(path, flags, 0o666)
        catch e
            (e isa Base.IOError && e.code == Base.UV_EEXIST) || rethrow()
        end
    end
    error("Could not find an unused file name for $name in $dir")
end

"""
```
    pdAttachmentExtract(att::PDAttachment, dir::AbstractString=".") -> String
```
Writes the attachment into the directory `dir` and returns the path of the file
written. Only the file name part of the attachment name is used. Existing files
are never overwritten. A numeric suffix is added to the file name instead.
"""
function pdAttachmentExtract(att::PDAttachment, dir::AbstractString=".")
    data = pdAttachmentGetData(att) # No file is created if decoding fails.
    mkpath(dir)
    path, io = create_new_file(dir, sanitize_filename(att.name))
    try
        write(io, data)
        close(io) # Can fail while flushing, hence inside the `try`.
    catch
        try close(io) catch end # The original error is the one to report.
        rm(path; force=true)    # Do not leave a partial file behind.
        rethrow()
    end
    return path
end

# Text strings are UTF-16BE or UTF-8 with a byte order mark, else PDFDocEncoding.
function pdf_text(str::CosString, fallback::String="attachment")
    b = Vector{UInt8}(str)
    if length(b) >= 2 && b[1] == 0xfe && b[2] == 0xff
        # An odd number of bytes is not valid UTF-16: do not truncate the name.
        isodd(length(b)) && return fallback
        u16 = UInt16[(UInt16(b[i]) << 8) | b[i+1] for i = 3:2:length(b)-1]
        s = transcode(String, u16)
        # An unpaired surrogate transcodes without error but leaves invalid
        # UTF-8 bytes behind (e.g. a lone high surrogate).
        return isvalid(s) ? s : fallback
    elseif length(b) >= 3 && b[1:3] == UInt8[0xef, 0xbb, 0xbf]
        return isvalid(String, b[4:end]) ? String(b[4:end]) : fallback
    end
    return String(CDTextString(PDFEncodingToUnicode(b)))
end

is_internal_stream(stm::CosStream) = stm.isInternal
is_internal_stream(stm::CosIndirectObject{CosStream}) = stm.obj.isInternal

# The file specification dictionary is resolved to the embedded file stream.
function attachment_from_filespec(cosdoc::CosDoc, fs::CosObject,
                                  fallback::String="attachment")
    fsdict = cosDocGetObject(cosdoc, fs)
    fsdict isa IDD{CosDict} || return nothing
    ef = cosDocGetObject(cosdoc, fsdict, cn"EF")
    ef isa IDD{CosDict} || return nothing
    stm = CosNull
    for key in (cn"F", cn"UF", cn"Unix", cn"Mac", cn"DOS") # Legacy keys are deprecated.
        stm = cosDocGetObject(cosdoc, ef, key)
        stm === CosNull || break
    end
    stm isa IDD{CosStream} || return nothing
    # A stream whose /F was supplied by the PDF itself (as opposed to one the
    # parser wrote out internally) refers to an arbitrary local file path.
    # Reading it would let a crafted PDF exfiltrate files readable by this
    # process, so such streams are not treated as attachments.
    is_internal_stream(stm) || return nothing
    name = fallback
    for key in (cn"UF", cn"F")
        nobj = cosDocGetObject(cosdoc, fsdict, key)
        nobj isa CosIndirectObject && (nobj = nobj.obj)
        if nobj isa CosString
            name = pdf_text(nobj, fallback)
            break
        end
    end
    return PDAttachment(name, stm)
end

# Walks a name tree calling `fn(key, value)` on every entry. `/Names` and `/Kids`
# may be indirect objects, hence they are resolved through the document.
function collect_nametree!(fn::Function, cosdoc::CosDoc, node::IDD{CosDict},
                           visited::Set{CosIndirectObjectRef})
    names = cosDocGetObject(cosdoc, node, cn"Names")
    if names isa IDD{CosArray}
        v = get(names)
        for i = 1:2:length(v)-1
            key = cosDocGetObject(cosdoc, v[i])
            fn(key isa CosString ? pdf_text(key) : "attachment", v[i+1])
        end
    end
    kids = cosDocGetObject(cosdoc, node, cn"Kids")
    kids isa IDD{CosArray} || return
    for kid in get(kids)
        if kid isa CosIndirectObjectRef
            kid in visited && continue
            push!(visited, kid)
        end
        kidobj = cosDocGetObject(cosdoc, kid)
        kidobj isa IDD{CosDict} && collect_nametree!(fn, cosdoc, kidobj, visited)
    end
end

"""
```
    pdDocGetAttachments(doc::PDDoc) -> Vector{PDAttachment}
```
Returns all the files embedded in the document. The files listed in the
`EmbeddedFiles` name tree are followed by the ones attached to the pages with
`FileAttachment` annotations. An embedded file referred in both the places is
returned once. Encrypted documents are not supported.

# Example
```
julia> pdDocGetAttachments(doc)
2-element Vector{PDAttachment}:
 PDAttachment("hello.txt")
 PDAttachment("data.bin")
```
"""
function pdDocGetAttachments(doc::PDDoc)
    cosdoc = pdDocGetCosDoc(doc)
    atts, seen = PDAttachment[], Set{Any}()
    function add!(fs, fallback="attachment")
        att = attachment_from_filespec(cosdoc, fs, fallback)
        att === nothing && return
        # Same embedded file stream can be referenced from multiple places.
        id = att.stream isa CosIndirectObject ?
            (att.stream.num, att.stream.gen) : objectid(att.stream)
        id in seen && return
        push!(seen, id)
        push!(atts, att)
    end

    names = pdDocGetNamesDict(doc)
    if names isa IDD{CosDict}
        ef = cosDocGetObject(cosdoc, names, cn"EmbeddedFiles")
        if ef isa IDD{CosDict}
            visited = Set{CosIndirectObjectRef}()
            collect_nametree!(cosdoc, ef, visited) do key, fs
                add!(fs, key)
            end
        end
    end

    for i = 1:pdDocGetPageCount(doc)
        cospage = pdPageGetCosObject(pdDocGetPage(doc, i))
        annots = cosDocGetObject(cosdoc, cospage, cn"Annots")
        annots isa IDD{CosArray} || continue
        for annot in get(annots)
            adict = cosDocGetObject(cosdoc, annot)
            adict isa IDD{CosDict} || continue
            cosDocGetObject(cosdoc, adict, cn"Subtype") === cn"FileAttachment" ||
                continue
            add!(cosDocGetObject(cosdoc, adict, cn"FS"))
        end
    end
    return atts
end

"""
```
    pdDocExtractAttachments(doc::PDDoc, dir::AbstractString=".") -> Vector{String}
```
Extracts all the files embedded in the document into the directory `dir`
(default is the current directory), creating it if required. Returns the paths
of the files written. See [`pdAttachmentExtract`](@ref).

# Example
```
julia> doc = pdDocOpen("invoice.pdf");

julia> pdDocExtractAttachments(doc)
1-element Vector{String}:
 "./invoice.xml"
```
"""
function pdDocExtractAttachments(doc::PDDoc, dir::AbstractString=".")
    return [pdAttachmentExtract(att, dir) for att in pdDocGetAttachments(doc)]
end

"""
```
    pdDocExtractAttachments(filepath::AbstractString, dir::AbstractString=".") -> Vector{String}
```
Convenience method that opens the PDF document at `filepath`, extracts every
file embedded in it into the directory `dir` (default is the current
directory), and closes the document. Returns the paths of the files written.
See [`pdDocExtractAttachments(::PDDoc, ::AbstractString)`](@ref).

# Example
```
julia> pdDocExtractAttachments("invoice.pdf")
1-element Vector{String}:
 "./invoice.xml"
```
"""
function pdDocExtractAttachments(filepath::AbstractString, dir::AbstractString=".")
    doc = pdDocOpen(filepath)
    try
        return pdDocExtractAttachments(doc, dir)
    finally
        pdDocClose(doc)
    end
end
