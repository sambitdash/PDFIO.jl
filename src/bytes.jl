export BACKSPACE, NULL,TAB, LINE_FEED,NEWLINE, FORM_FEED, RETURN,
       SPACE, STRING_DELIM, PLUS_SIGN, DELIMITER, MINUS_SIGN,
       DECIMAL_POINT, SOLIDUS, DIGIT_ZERO, DIGIT_NINE, SEPARATOR,
       LATIN_UPPER_A, LATIN_UPPER_F, LATIN_UPPER_I, BACKSLASH, LATIN_A, LATIN_B,LATIN_E,
       LATIN_F, LATIN_I, LATIN_L, LATIN_N, LATIN_R, LATIN_S, LATIN_T, LATIN_U,LATIN_Z,
       OBJECT_BEGIN, OBJECT_END, ESCAPES, REVERSE_ESCAPES,
       LEFT_PAREN, RIGHT_PAREN, LESS_THAN,
       GREATER_THAN, LEFT_CB, RIGHT_CB, LEFT_SB, RIGHT_SB,
       PERCENT,PERIOD, NUMBER_SIGN, BANG, TILDE, LATIN_UPPER_D,STREAM,ENDSTREAM,
       LATIN_UPPER_E,LATIN_UPPER_F, LATIN_UPPER_O, LATIN_UPPER_P,
       LATIN_UPPER_R,XREF, TRAILER, STARTXREF, EOF, OBJ, ENDOBJ, ispdfspace,
       ispdfdelimiter, ispdfdigit, ispdfodigit, ispdfxdigit, gethexval, getnumval, is_crorlf



# The following bytes have significant meaning in PDF
const NULL           = UInt8('\0')
const TAB            = UInt8('\t')
const LINE_FEED      = UInt8('\n')
const FORM_FEED      = UInt8('\f')
const RETURN         = UInt8('\r')
const SPACE          = UInt8(' ')

const BACKSPACE      = UInt8('\b')

const LEFT_PAREN     = UInt8('(')
const RIGHT_PAREN    = UInt8(')')
const LESS_THAN      = UInt8('<')
const GREATER_THAN   = UInt8('>')
const LEFT_CB        = UInt8('{')
const RIGHT_CB       = UInt8('}')
const LEFT_SB        = UInt8('[')
const RIGHT_SB       = UInt8(']')

const PERCENT        = UInt8('%')
const PERIOD         = UInt8('.')
const NUMBER_SIGN    = UInt8('#')
const BANG           = UInt8('!')
const TILDE          = UInt8('~')

const STRING_DELIM   = UInt8('"')
const PLUS_SIGN      = UInt8('+')
const DELIMITER      = UInt8(',')
const MINUS_SIGN     = UInt8('-')
const DECIMAL_POINT  = UInt8('.')
const SOLIDUS        = UInt8('/')
const DIGIT_ZERO     = UInt8('0')
const DIGIT_ONE      = UInt8('1')
const DIGIT_SEVEN    = UInt8('7')
const DIGIT_NINE     = UInt8('9')
const SEPARATOR      = UInt8(':')
const LATIN_UPPER_A  = UInt8('A')
const LATIN_UPPER_D  = UInt8('D')
const LATIN_UPPER_E  = UInt8('E')
const LATIN_UPPER_F  = UInt8('F')
const LATIN_UPPER_I  = UInt8('I')
const LATIN_UPPER_M  = UInt8('M')
const LATIN_UPPER_O  = UInt8('O')
const LATIN_UPPER_P  = UInt8('P')
const LATIN_UPPER_R  = UInt8('R')


const BACKSLASH      = UInt8('\\')

const LATIN_A        = UInt8('a')
const LATIN_B        = UInt8('b')
const LATIN_D        = UInt8('d')
const LATIN_E        = UInt8('e')
const LATIN_F        = UInt8('f')
const LATIN_I        = UInt8('i')
const LATIN_J        = UInt8('j')
const LATIN_L        = UInt8('l')
const LATIN_M        = UInt8('m')
const LATIN_N        = UInt8('n')
const LATIN_O        = UInt8('o')
const LATIN_R        = UInt8('r')
const LATIN_S        = UInt8('s')
const LATIN_T        = UInt8('t')
const LATIN_U        = UInt8('u')
const LATIN_X        = UInt8('x')
const LATIN_Z        = UInt8('z')


const ESCAPES = Dict(
    LEFT_PAREN   => LEFT_PAREN,
    RIGHT_PAREN  => RIGHT_PAREN,
    BACKSLASH    => BACKSLASH,
    LATIN_B      => BACKSPACE,
    LATIN_F      => FORM_FEED,
    LATIN_N      => LINE_FEED,
    LATIN_R      => RETURN,
    LATIN_T      => TAB)

#=
const REVERSE_ESCAPES = Dict(map(reverse, ESCAPES))
const ESCAPED_ARRAY = Vector{Vector{UInt8}}(256)
for c in 0x00:0xFF
    ESCAPED_ARRAY[c + 1] =
        if c == SOLIDUS
            [SOLIDUS]  # don't escape this one
        elseif c ≥ 0x80
            [c]  # UTF-8 character copied verbatim
        elseif haskey(REVERSE_ESCAPES, c)
            [BACKSLASH, REVERSE_ESCAPES[c]]
        elseif iscntrl(@compat Char(c)) || !isprint(@compat Char(c))
            UInt8[BACKSLASH, LATIN_U, hex(c, 4)...]
        else
            [c]
        end
end
=#

const XREF     =[LATIN_X,LATIN_R,LATIN_E,LATIN_F]
const TRAILER  =[LATIN_T,LATIN_R,LATIN_A,LATIN_I,LATIN_L,LATIN_E,LATIN_R]
const STARTXREF=[LATIN_S,LATIN_T,LATIN_A,LATIN_R,LATIN_T,LATIN_X,LATIN_R,LATIN_E,LATIN_F]
const EOF      =[PERCENT,PERCENT,LATIN_UPPER_E,LATIN_UPPER_O,LATIN_UPPER_F]
const OBJ      =[LATIN_O,LATIN_B,LATIN_J]
const ENDOBJ   =[LATIN_E,LATIN_N,LATIN_D,LATIN_O,LATIN_B,LATIN_J]
const STREAM   =[LATIN_S,LATIN_T,LATIN_R,LATIN_E,LATIN_A,LATIN_M]
const ENDSTREAM=[LATIN_E,LATIN_N,LATIN_D,LATIN_S,LATIN_T,LATIN_R,LATIN_E,LATIN_A,LATIN_M]


"""
Like `isspace`, but work on bytes and includes only the four whitespace
characters defined by the PDF standard: null, space, tab, line feed,
form feed, and carriage return.
"""
ispdfspace(b::UInt8) = b == NULL || b == TAB || b == LINE_FEED || b == RETURN || b == FORM_FEED || b == SPACE

ispdfdelimiter(b::UInt8) = (b == LEFT_PAREN || b == RIGHT_PAREN || b == LESS_THAN ||
                            b == GREATER_THAN || b == LEFT_CB || b == RIGHT_CB ||
                            b == LEFT_SB || b == RIGHT_SB || b == PERCENT || b == SOLIDUS)


"""
Like `isdigit`, but for bytes.
"""
ispdfdigit(b::UInt8) = (DIGIT_ZERO ≤ b ≤ DIGIT_NINE)

"""
Like `isdigit`, but for bytes.
"""
ispdfodigit(b::UInt8) = (DIGIT_ZERO ≤ b ≤ DIGIT_SEVEN)

ispdfxdigit(b::UInt8) =
    (ispdfdigit(b) || (LATIN_UPPER_A <= b <= LATIN_UPPER_F) || (LATIN_A <= b <= LATIN_F))

gethexval(b::UInt8) =   (DIGIT_ZERO <= b <= DIGIT_NINE) ? b - DIGIT_ZERO :
                        (LATIN_UPPER_A <= b <= LATIN_UPPER_F) ? b - LATIN_UPPER_A + 0xa :
                        (LATIN_A <= b <= LATIN_F) ? b - LATIN_A + 0xa :
                        throw(ErrorException(E_BAD_NUMBER))

getnumval(b::UInt8) =   (DIGIT_ZERO <= b <= DIGIT_NINE) ? b - DIGIT_ZERO :
                        throw(ErrorException(E_BAD_NUMBER))

is_crorlf(b::UInt8) = ((b == RETURN) ||(b == LINE_FEED))
