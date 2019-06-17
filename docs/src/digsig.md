# Digital Signatures

The integrity of a PDF document can be protected by using **digital**
**signatures**. The signatures can be of various kinds; namely,
signature images, biometric information as well as mathematical
equations as in Public Key Infrastructure (PKI) based
signatures. While PDF documents can support these varied signature
schemes, the API designed here is only limited to the interoperable
signature schemes related to PKI certificates described in the PDF
specification section 12.8.3. PKI standards are fairly involved set of
operations, and exhaustive explanation of these operations cannot be
possible in this section. Some high level concepts are described here
for the API user to get familiarity of the operations.

## Basics of Public Key Infrastructure (PKI)

When Alice wants to send a PDF document to Bob, Bob would like to
understand if:

1. Alice only sent the document
2. The document he got is what Alice intended to send and not a
   tampered version.

Digital signature schemes address these problems. **Public Key
Infrastructure (PKI)** provides one such solution to the problem. It
expects Alice to own two keys, one **private key (K<sub>v</sub>)**,
that she has to keep absolutely secretly under her possession and a
second one called **public key (K<sub>p</sub>)** that she has to
provide to Bob. When an information is encoded using the private key
(K<sub>v</sub>), it can only be decoded by the public key
(K<sub>p</sub>) thus **verifying** the operation. This is the
foundation of the **asymmetric cryptography**.

Following are the **digital signing** operations as carried out by
Alice:

1. Alice creates a **digest** of the PDF document using a **digest
   algorithm**.
   1. The digest is a one way derivative of the document, that cannot
      be reverse engineered to get back to the original document.
   2. The digest algorithms are such that even the slightest change in
      the document will have a digest that is completely different
      from the original digest.
2. Alice encodes the digest **plain text** using K<sub>v</sub>. This
   encoded **cipher text** is called the **signature**.
3. Alice embeds the signature, the digest algorithm she used in in the
   PDF document and sends it to Bob.

Bob uses the following **validation** or **verification** steps:

1. Bob computes the digest of the document using the same algorithm
   Alice used by picking up the information from the PDF.
2. He picks up the cipher text from the signature and applies decoding
   method using K<sub>p</sub>.
3. The plain text thus obtained is compared with the digest generated
   in step 1 to ensure the document has not been tampered with.

The APIs developed here are confined to the validation and
verification operations only and does not encompass the signing
operations.

## Digital Certificates

One problem which has still not been addressed in the previous example
is how can Alice communicate to Bob her public key
(K<sub>p</sub>). This is a significant concern in the internet world
as Alice and Bob may never meet in person. Secondly, Alice may have to
communicate to many other people and not just Bob and such information
exchange needs a standardized framework so that she can provide same
information to all the people she can interact with. She can contact a
**certifying authority (CA)** and provide her public key
(K<sub>p</sub>) and other personal details like name, contact
etc. which will be signed by the private key of the CA and presented
in a standardized format. The process is called **issuance of
certificates** and the digital information Alice receives is called a
**X509 certificate** or a **certificate**. Any person who has Alice's
digital certificate can essentially validate the authenticity of the
certificate by verifying with the CA's public key.

### Chain of Trust

In a distributed world, a single CA is hard to conceive and not
scalable to issue and manage all the certificates. Thus, CAs typically
establish a network of subordinate CAs who can manage certificates on
their behalf by issuing additional certificates that can be used as
CAs to issue further certificates downstream. This leads to one **root
certifying authority** or **root** and large number of **subordinate
certifying authority** or **intermediate CA**. The root CA certificate
is issued by the root CA itself. This process is called
**self-signing**. A certificate that is actually used for any
operation (like signing of documents) also known as **end entity
certificate** is **trusted** only when the root as well as all
intermediate CA certificates that were used to validate the
certificates are trust worthy. This essentially means the certificate
of all such CAs will be validated against their respective CA
certificates establishing a chain of trust.

### Trust Store

Any applications validating a certificate needs to maintain a trust
store of certificates. A trust store must contain the root and all
intermediate CA certificates to be able to validate an end entity
certificates.

The API uses the file: `<PDFIO Dir>/data/certs/cacerts.pem` as a
certificate trust store.

An end-entity certificate included in the trust store is not validated
for establishing a chain of trust. Hence, is generally
discouraged. However, in case of self-signed certificates this may be
the only means to establish trust.

### Expiry and Revocation

#### Importance of Time

Asymmetric encryption works because of the following two inherent
assumptions:

1. The digest algorithm is strong enough so that one cannot find
   another document that easily which will reproduce the same digest
   even when a large number of computing resources are provided within
   a reasonable time.
2. Knowing the public key one cannot possibly find a private key using large 
   number  of computing resources within a reasonable time.

Hence, as computing power improves, there is a consistent need to
search for algorithms that keep the assumption valid. Hence, as a
policy certificates are kept ephemeral, only being valid for one to
three years. As a policy of verification the time validity of all the
certificates are reviewed as well.

#### Certificate Revocation

A valid certificate can be **revoked** by a CA if it's found that the
certificate was compromised in some manner. A compromise includes
exposure of private key by any means to any undesirable party. Such
information can be periodically updated in a ledger by a CA that can
be downloaded by the clients. These are called as **Certificate
Revocation Lists (CRL)**. With internet being so much more popular the
certificates can be queried with the CA intermittently for their
validity using the **Online Certificate Security Protocol (OCSP)**
rather than a lookup on the cached CRLs. Certificate validation
process includes referring to the said databases for revocation
information.

## Signature Validity

Signature in a document is said to be valid when:

1. The certificate which it's to be validated against is valid when
   the signature was computed. This shall mean:
   1. The certificate had not expired
   2. The certificate had not been revoked by the issuing CA
   3. A complete trust chain can be established of valid certificates
2. It can be established the signature was originated from the content
   that it claims to represent.
3. The certificate used for signing is the valid certificate for the
   purpose, policy defined and of the profiles that such a certificate
   should have. **Purpose**, **policy** and **profile** mandate
   certain **attributes** that must be defined in a certificate. They
   also establish certain constraints in their relationships.

Since, time is an important factor in validating certificates, the
same can affect signatures as well. Signatures can be validated at the
time when they were generated if such information is available with
the document. Otherwise, the signatures are validated in the current
time.

## Digital Signatures in PDF

As per the PDF specification, the following functions can be carried
out with signing of PDF files:

1. Signing and embedding a signature in the document
2. Validation of the signature
3. Granular control of PDF document objects based on the permissions
   enabled with validation of a signature. (DocMDP, UR and FieldMDP)
4. Incremental updates to the document with changes preserved for
   authoritative version management.
5. Defining a document secured store and populating validation related
   information (PDF-2.0).
6. Creating a document time stamp and ensuring that is updated
   effectively for long time validation of signatures when the
   certificates may expire or become invalid due to weaker cipher
   specification in them (PDF-2.0).

## API and its Limitations

The API provided here is a single method
`pdDocValidateSignatures`. The method provides the following two
functionalities:

1. Scans the PDF document for approval signatures appearing in the
   document as form fields and validates those. For each such
   signature it returns a status dictionary with certificate details,
   pass status of the validation or failures and failure reasons if
   any.
2. Given an optional parameter, exports all the certificates embedded
   in the PDF document so that the they can be reviewed and
   intermediate and root certificates can be picked up and added to
   the trusted certificate store.
   
The functionality in terms of validation is fairly basic and does not 
review the policies, profiles or purpose of the certificates.

## Reference

1. Digital Signature article on [Wikipedia](https://en.wikipedia.org/wiki/Digital_signature)
2. Adobe Systems Inc. (2008) Document Management - Portable Document
   Format - Part 1: PDF 1.7, retrieved from [Adobe](https://www.adobe.com/devnet/pdf/pdf_reference.html).
