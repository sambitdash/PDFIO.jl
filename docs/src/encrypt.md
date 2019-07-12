# Encryption in PDF

PDF files can be encrypted across the complete file or selectively for
specific sections. The encryption scheme used in PDFs can be based on
the PDF standard specification or can be controlled by custom schemes
developed by the PDF creators. These flexibilities can be achieved by
the following security handlers of the PDF processors.

1. Password based Standard Security Handlers
2. PKI certificate based Public Key Security Handlers
3. Crypt filters that can be used for specific streams in a PDF
   document

# Encryption Methods

## What can be encrypted?
Not all information in a PDF file is encrypted. Only the streams and
strings that tend to have informational content are
encrypted. Integers, booleans or any such information that is only
structural are not encrypted. Document metadata that can be used for
search and other information extraction process need not be encrypted
in a PDF document. Secondly, care is always taken such that content is
not encrypted multiple number of times. For example, only one
encryption filter is permitted in a stream. Once such a filter is
specifically chosen for a stream the document default filters are not
applicable to such streams. Strings that are part of object streams
that are encrypted are excluded from further encryption.

## Process of Encryption
PDF encryption is based on a symmetric key algorithm based on older
RC4 or AES-128 bit schemes or modern AES-256 bit encryption
algorithms. These methods require a 40, 128 or 256 bit key be used to
encrypt or decrypt the PDF document. Since, the key has to be kept
inside the PDF document, password based approaches or PKI Certificate
based approaches are taken to secure the encryption key. One
encryption key is used per crypt filter and once the API successfully
manages to decrypt the key it can be caches securedly for subsequent
operations.

### Standard Security Handlers
Standard security handler provides a flexible mechanism of securing
the file encryption key using two passwords. Namely, document open
password (user password) and document permission (owner password). A
document may not have a user password. In such cases, providing a
blank string as input can open the document. However, it must be noted
that the file encryption key is still used in these cases as well. And
such document is not equivalent to a document without passwords. Owner
password defaults to the user password if it's not explicitly set. The
older RC4 or AES-128bit encryption schemes were based on user password
being used to encrypt the file encryption key and owner password being
used to encrypt the user password. However, the modern AES-256bit
system utilizes a hashed based validation than encrypting one password
with the other. However, either the owner password or the user
password can be used to retrieve the document encryption key.

### Public Key Security Handlers
Public key security handler utilizes the public key of a digital
certificate to encrypt the file encryption key that can be only be
decrypted by a specific set of recipients whose public key was used to
encrypt the file encryption keys. Again, the document can be decrypted
only by the recipient on successful production of the private key of
the certificate.

### Permissions
PDF specification provides permissions for users different from that
of the owners. Owners have no usage restriction while users can be
limited by certain permissions. The permissions are expected to be
enforced by the reader applications. Once decrypted there is no way
to technically encfore limitations. In the context of the API, we do
not restrict any APIs but expect the consumer of the APIs to enforce
the permissions as desired. The permission can be found in the
security handlers keys dictionary mapped to each crypt filter. The
permissions can be accessed by:

`cosdoc.secHandler.keys[<Crypt Filter Name>][1]`

When the user password is used to authenticate the document permission
entry is cached. However, when an owner password is used the value
cached is `0xffffffff` signifying all the permissions are available.

### Prompting for Access
As discussed earlier, not all PDF content may be encrypted. Hence, the
prompting for password or token to decrypt (in case of PKI security
handler) can occur when such a need is felt. When a particular piece
of content requires decryption in case of a standard security handler
a `Base.getpass()` based challenge is thrown on the `stdout`. However,
this may not be a convenient way to programatically utilize and
API. The following APIs provide additional keyword `access=predicate`
as a way to override the default behavior. Following is an example of
a `pdDocOpen` call utilizing a fixed password as input.

```
doc = pdDocOpen("file.pdf", access=()->Base.SecretBuffer!(copy(b"password")))
```
The same interface can be used with the method `cosDocOpen` as well. 

### Keeping Access Secured
It must have come to you as a surprise the usage of such a complex
predicate for passing a simple password. However, `String` objects
being immutable, it's never a desired in security applications to have
secured information lying in the memory indefinitely as
`String`s. While `Vector{UInt8}` objects get reclaimed, the underlying
memory is never overwritten leaving out secured information in the
memory to be harvested with crash dumps, pagefile or memory
walks. `Base.SecureBuffer` comes handy in such cases as it clears off
the underlying memory to `zero` or provides a `shred!` method that can
be utilized to clear off the memory on demand. The predicate must
return a `Base.SecretBuffer` object to be consumed by the security
handler.

### Caching of the File Encryption Key
Just as much like the password, the computed file encyption key is a
crucial piece of information that is cached in the memory with the
security handler object. Although, it resides at:
`cosdoc.secHandler.keys[<Crypt Filter Name>][2]`. It's encrypted with
a symmetric key and nonce generated during the initialization of the
secuirty handler and cached to a temporary file. When a decryption
task is to be carried out the key and nonce are secured from the file
and used to decrypt the file encryption key. As soon as the task is
over the file encryption keys are `shred!`ed by a `SecureBuffer`
interface. Thus a random dump of memory may neither have the password
nor the file encryption key resident in memory. With the API
being open source we do not expect to provide any protection against
debugging. 

### PKI Security Handler
PKI security handler can be used to decrypt PDF documents if
needed. The handler will be invoked when needed to decrypt data very
similar to the standard security handler. The default method provides
capabilities to decrypt the document using a PKCS#12 (.p12) file as a
keystore. However, the default behavior can be easily overwritten by
providing your own access function. The default code looks like below:

```
function get_digital_id()
    p12file = ""
    while !isfile(p12file)
        p12file =
            prompt("Select the PCKS#12 (.p12) certificate for the recepient")
    end
    p12pass = getpass("Enter the password to open the PKCS#12 (.p12) file")
    return shred!(x->read_pkcs12(p12file, x), p12pass)
end

doc = pdDocOpen("file.pdf", access=get_digital_id)
```

The functionality has been developed with `OpenSSL`. OpenSSL `ENGINE`
interface can be used to implement another version of `get_digital_id`
method using a `PKCS#11` based interface to enable HSM or hardware
tokens as certificate stores.
