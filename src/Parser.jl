module Parser

import Base.read
import Base.seekend
import Base.position
import Base.seek
import Base.hash
import Base.parse

using PDF.Common

using Compat

export ParserState,
       getParserState,
       skip!,
       advance!,
       byteat,
       locate_keyword!,
       chomp_space!,
       chomp_eol!,
       current,
       hasmore,
       incr!
       read!

abstract ParserState

type MemoryParserState <: ParserState
    utf8data::Vector{UInt8}
    s::Int
end

type StreamingParserState{T <: IO} <: ParserState
    io::T
    cur::UInt8
    used::Bool
end

StreamingParserState{T <: IO}(io::T) = StreamingParserState{T}(io, 0x00, true)

function getParserState{T <: IO}(io::T)
  return StreamingParserState(io)
end

@inline position(ps::StreamingParserState)=position(ps.io)
@inline position(ps::MemoryParserState)=(ps.s)

"""
Seek a stream
"""
@inline function seek(ps::StreamingParserState, pos::Int64)
    ps.used=true
    if (pos < 0)
        seekend(ps.io)
        len = position(ps.io)
        pos += len
    end
    return seek(ps.io,pos)
end

@inline seekstart(ps::StreamingParserState)=seekstart(ps.io)
@inline seekend(ps::StreamingParserState)=seekend(ps.io)

@inline function read!(ps::StreamingParserState, nb::Int)
    data=read(ps.io, nb)
    ps.cur =0
    ps.used=true
    return data
end

@inline function read!(ps::MemoryParserState, nb::Int)
    data=getindex(ps.utf8data,ps.s:ps.s+nb-1)
    ps.s += nb
    return data
end

"""
Return the byte at the current position of the `ParserState`. If there is no
byte (that is, the `ParserState` is done), then an error is thrown that the
input ended unexpectedly.
"""
@inline function byteat(ps::MemoryParserState)
    @inbounds if hasmore(ps)
        return ps.utf8data[ps.s]
    else
        _error(E_UNEXPECTED_EOF, ps)
    end
end

@inline function byteat(ps::StreamingParserState)
    if ps.used
        ps.used = false
        if eof(ps.io)
            _error(E_UNEXPECTED_EOF, ps)
        else
            ps.cur = read(ps.io, UInt8)
        end
    end
    ps.cur
end

"""
Move the `ParserState` to the previous byte
"""
@inline retract!(ps::StreamingParserState) = (ps.used = false; ps.cur)
@inline retract!(ps::MemoryParserState) = (ps.s -= 1)


"""
Like `byteat`, but with no special bounds check and error message. Useful when
a current byte is known to exist.
"""
@inline current(ps::MemoryParserState) = ps.utf8data[ps.s]
@inline current(ps::StreamingParserState) = byteat(ps)

"""
Require the current byte of the `ParserState` to be the given byte, and then
skip past that byte. Otherwise, an error is thrown.
"""
@inline function skip!(ps::ParserState, c::UInt8)
    if byteat(ps) == c
        incr!(ps)
    else
        _error("Expected '$(Char(c))' here", ps)
    end
end

function skip!(ps::ParserState, cs::UInt8...)
    for c in cs
        skip!(ps, c)
    end
end

function skip!(ps::ParserState, cs::Array{UInt8,1})
    for c in cs
        skip!(ps, c)
    end
end

"""
Move the `ParserState` to the next byte.
"""
@inline incr!(ps::MemoryParserState) = (ps.s += 1)
@inline incr!(ps::StreamingParserState) = (ps.used = true)

"""
Move the `ParserState` to the next byte, and return the value at the byte before
the advancement. If the `ParserState` is already done, then throw an error.
"""
@inline advance!(ps::ParserState) = (b = byteat(ps); incr!(ps); b)


"""
Return `true` if there is a current byte, and `false` if all bytes have been
exausted.
"""
@inline hasmore(ps::MemoryParserState) = ps.s ≤ endof(ps.utf8data)
@inline hasmore(ps::StreamingParserState) = true  # no more now ≠ no more ever

"""
Remove as many whitespace bytes as possible from the `ParserState` starting from
the current byte.
"""
@inline function chomp_space!(ps::ParserState)
    @inbounds while hasmore(ps) && ispdfspace(current(ps))
        incr!(ps)
    end
end

@inline function chomp_eol!(ps::ParserState)
    @inbounds while hasmore(ps) && is_crorlf(current(ps))
        incr!(ps)
    end
end


# Used for line counts
function _count_before(haystack::AbstractString, needle::Char, _end::Int)
    count = 0
    for (i,c) in enumerate(haystack)
        i >= _end && return count
        count += c == needle
    end
    return count
end


# Throws an error message with an indicator to the source
function _error(message::AbstractString, ps::MemoryParserState)
    orig = String(ps.utf8data)
    lines = _count_before(orig, '\n', ps.s)
    # Replace all special multi-line/multi-space characters with a space.
    strnl = replace(orig, r"[\b\f\n\r\t\s]", " ")
    li = (ps.s > 20) ? ps.s - 9 : 1 # Left index
    ri = min(endof(orig), ps.s + 20)       # Right index
    error(message *
      "\nLine: " * string(lines) *
      "\nAround: ..." * strnl[li:ri] * "..." *
      "\n           " * (" " ^ (ps.s - li)) * "^\n"
    )
end

function _error(message::AbstractString, ps::StreamingParserState)
    error("$message\n ...when parsing byte with value '$(current(ps))'")
end

function kmp_preprocess(P)
    m = length(P)
    pi = Vector{Int}(m)
    pi[1] = 0
    k = 0
    for q = 2:m
        while k > 0 && P[k+1] != P[q]
            k = pi[k]
        end
        if P[k+1] == P[q]
            k += 1
        end
        pi[q] = k
    end
    return pi
end

function locate_keyword!(ps::ParserState, keyword, maxoffset=length(keyword))
    m = length(keyword)
    pi = kmp_preprocess(keyword)

    q = 0
    found=false
    offset = -1
    pos = position(ps)

    while(true)
        c = advance!(ps)
        offset += 1
        while q > 0 && keyword[q+1] != c
            q = pi[q]
        end
        if keyword[q+1] == c
            q +=1
        end
        if q == m
            found = true
            q = pi[q]
            break
        end
        if (offset >= maxoffset)
          break
        end
    end
    if found
      return (offset - length(keyword))
    else
      seek(ps, pos)
      byteat(ps)
      return -1
    end
end

# Efficient implementations of some of the above for in-memory parsing
include("specialized.jl")


end  # module Parser
