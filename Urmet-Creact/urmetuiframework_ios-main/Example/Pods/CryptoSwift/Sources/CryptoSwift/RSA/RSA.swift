//
//  CryptoSwift
//
//  Copyright (C) 2014-2022 Marcin Krzyżanowski <marcin@krzyzanowskim.com>
//  This software is provided 'as-is', without any express or implied warranty.
//
//  In no event will the authors be held liable for any damages arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:
//
//  - The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation is required.
//  - Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
//  - This notice may not be removed or altered from any source or binary distribution.
//

// Foundation is required for `Data` to be found
import Foundation

// Note: The `BigUInt` struct was copied from:
// https://github.com/attaswift/BigInt
// It allows fast calculation for RSA big numbers

public final class RSA: DERCodable {
    /// RSA Key Errors
    public enum Error: Swift.Error {
        /// No private key specified
        case noPrivateKey
        /// Failed to calculate the inverse e and phi
        case invalidInverseNotCoprimes
        /// We only support Version 0 RSA keys (we don't support Version 1 introduced in RFC 3447)
        case unsupportedRSAVersion
        /// Failed to verify primes during initialiization (the provided primes don't reproduce the provided private exponent)
        case invalidPrimes
        /// We attempted to export a private key without our underlying primes
        case noPrimes
        /// Unable to calculate the coefficient during a private key import / export
        case unableToCalculateCoefficient
        /// The signature to verify is of an invalid length
        case invalidSignatureLength
        /// The message to be signed is of an invalid length
        case invalidMessageLengthForSigning
        /// The message to be encrypted is of an invalid length
        case invalidMessageLengthForEncryption
        /// The error thrown when Decryption fails
        case invalidDecryption
    }

    /// RSA Modulus
    public let n: BigUInteger

    /// RSA Public Exponent
    public let e: BigUInteger

    /// RSA Private Exponent
    public let d: BigUInteger?

    /// The size of the modulus, in bits
    public let keySize: Int

    /// The size of the modulus, in bytes (rounded up to the nearest full byte)
    public let keySizeBytes: Int

    /// The underlying primes used to generate the Private Exponent
    private let primes: (p: BigUInteger, q: BigUInteger)?

    /// Initialize with RSA parameters
    /// - Parameters:
    ///   - n: The RSA Modulus
    ///   - e: The RSA Public Exponent
    ///   - d: The RSA Private Exponent (or nil if unknown, e.g. if only public key is known)
    public init(n: BigUInteger, e: BigUInteger, d: BigUInteger? = nil) {
        self.n = n
        self.e = e
        self.d = d
        primes = nil

        keySize = n.bitWidth
        keySizeBytes = n.byteWidth
    }

    /// Initialize with RSA parameters
    /// - Parameters:
    ///   - n: The RSA Modulus
    ///   - e: The RSA Public Exponent
    ///   - d: The RSA Private Exponent (or nil if unknown, e.g. if only public key is known)
    public convenience init(n: [UInt8], e: [UInt8], d: [UInt8]? = nil) {
        if let d = d {
            self.init(n: BigUInteger(Data(n)), e: BigUInteger(Data(e)), d: BigUInteger(Data(d)))
        } else {
            self.init(n: BigUInteger(Data(n)), e: BigUInteger(Data(e)))
        }
    }

    /// Initialize with a generated key pair
    /// - Parameter keySize: The size of the modulus
    public convenience init(keySize: Int) throws {
        // Generate prime numbers
        let p = BigUInteger.generatePrime(keySize / 2)
        let q = BigUInteger.generatePrime(keySize / 2)

        // Calculate modulus
        let n = p * q

        // Calculate public and private exponent
        let e: BigUInteger = 65537
        let phi = (p - 1) * (q - 1)
        guard let d = e.inverse(phi) else {
            throw RSA.Error.invalidInverseNotCoprimes
        }

        // Initialize
        self.init(n: n, e: e, d: d, p: p, q: q)
    }

    /// Initialize with RSA parameters
    /// - Parameters:
    ///   - n: The RSA Modulus
    ///   - e: The RSA Public Exponent
    ///   - d: The RSA Private Exponent
    ///   - p: The 1st Prime used to generate the Private Exponent
    ///   - q: The 2nd Prime used to generate the Private Exponent
    private init(n: BigUInteger, e: BigUInteger, d: BigUInteger, p: BigUInteger, q: BigUInteger) {
        self.n = n
        self.e = e
        self.d = d
        primes = (p, q)

        keySize = n.bitWidth
        keySizeBytes = n.byteWidth
    }
}

// MARK: BigUInt Extension

internal extension CS.BigUInt {
    /// The minimum number of bytes required to represent this integer in binary.
    var byteWidth: Int {
        let bytes = bitWidth / 8
        return bitWidth % 8 == 0 ? bytes : bytes + 1
    }
}

// MARK: DER Initializers (See #892)

extension RSA {
    /// Decodes the provided data into a Public RSA Key
    ///
    /// [IETF Spec RFC2313](https://datatracker.ietf.org/doc/html/rfc2313#section-7.1)
    /// ```
    /// =========================
    ///  RSA PublicKey Structure
    /// =========================
    ///
    /// RSAPublicKey ::= SEQUENCE {
    ///   modulus           INTEGER,  -- n
    ///   publicExponent    INTEGER,  -- e
    /// }
    /// ```
    internal convenience init(publicDER der: [UInt8]) throws {
        let asn = try ASN1.Decoder.decode(data: Data(der))

        // Enforce the above ASN Structure
        guard case let .sequence(params) = asn else { throw DER.Error.invalidDERFormat }
        guard params.count == 2 else { throw DER.Error.invalidDERFormat }

        guard case let .integer(modulus) = params[0] else { throw DER.Error.invalidDERFormat }
        guard case let .integer(publicExponent) = params[1] else { throw DER.Error.invalidDERFormat }

        self.init(n: BigUInteger(modulus), e: BigUInteger(publicExponent))
    }

    /// Decodes the provided data into a Private RSA Key
    ///
    /// [IETF Spec RFC2313](https://datatracker.ietf.org/doc/html/rfc2313#section-7.2)
    /// ```
    /// ==========================
    ///  RSA PrivateKey Structure
    /// ==========================
    ///
    /// RSAPrivateKey ::= SEQUENCE {
    ///   version           Version,
    ///   modulus           INTEGER,  -- n
    ///   publicExponent    INTEGER,  -- e
    ///   privateExponent   INTEGER,  -- d
    ///   prime1            INTEGER,  -- p
    ///   prime2            INTEGER,  -- q
    ///   exponent1         INTEGER,  -- d mod (p-1)
    ///   exponent2         INTEGER,  -- d mod (q-1)
    ///   coefficient       INTEGER,  -- (inverse of q) mod p
    /// }
    /// ```
    internal convenience init(privateDER der: [UInt8]) throws {
        let asn = try ASN1.Decoder.decode(data: Data(der))

        // Enforce the above ASN Structure (do we need to extract and verify the eponents and coefficients?)
        guard case let .sequence(params) = asn else { throw DER.Error.invalidDERFormat }
        guard params.count == 9 else { throw DER.Error.invalidDERFormat }
        guard case let .integer(version) = params[0] else { throw DER.Error.invalidDERFormat }
        guard case let .integer(modulus) = params[1] else { throw DER.Error.invalidDERFormat }
        guard case let .integer(publicExponent) = params[2] else { throw DER.Error.invalidDERFormat }
        guard case let .integer(privateExponent) = params[3] else { throw DER.Error.invalidDERFormat }
        guard case let .integer(prime1) = params[4] else { throw DER.Error.invalidDERFormat }
        guard case let .integer(prime2) = params[5] else { throw DER.Error.invalidDERFormat }
        guard case let .integer(exponent1) = params[6] else { throw DER.Error.invalidDERFormat }
        guard case let .integer(exponent2) = params[7] else { throw DER.Error.invalidDERFormat }
        guard case let .integer(coefficient) = params[8] else { throw DER.Error.invalidDERFormat }

        // We only support version 0x00 == RFC2313 at the moment
        // - TODO: Support multiple primes 0x01 version defined in [RFC3447](https://www.rfc-editor.org/rfc/rfc3447#appendix-A.1.2)
        guard version == Data(hex: "0x00") else { throw Error.unsupportedRSAVersion }

        // Ensure the supplied parameters are correct...
        // Calculate modulus
        guard BigUInteger(modulus) == BigUInteger(prime1) * BigUInteger(prime2) else { throw Error.invalidPrimes }

        // Calculate public and private exponent
        let phi = (BigUInteger(prime1) - 1) * (BigUInteger(prime2) - 1)
        guard let d = BigUInteger(publicExponent).inverse(phi) else { throw Error.invalidPrimes }
        guard BigUInteger(privateExponent) == d else { throw Error.invalidPrimes }

        // Ensure the provided coefficient is correct (derived from the primes)
        guard let calculatedCoefficient = BigUInteger(prime2).inverse(BigUInteger(prime1)) else { throw RSA.Error.unableToCalculateCoefficient }
        guard calculatedCoefficient == BigUInteger(coefficient) else { throw RSA.Error.invalidPrimes }

        // Ensure the provided exponents are correct as well
        guard (d % (BigUInteger(prime1) - 1)) == BigUInteger(exponent1) else { throw RSA.Error.invalidPrimes }
        guard (d % (BigUInteger(prime2) - 1)) == BigUInteger(exponent2) else { throw RSA.Error.invalidPrimes }

        // Proceed with regular initialization
        self.init(n: BigUInteger(modulus), e: BigUInteger(publicExponent), d: BigUInteger(privateExponent), p: BigUInteger(prime1), q: BigUInteger(prime2))
    }

    /// Attempts to instantiate an RSA Key when given the ASN1 DER encoded external representation of the Key
    ///
    /// An example of importing a SecKey RSA key (from Apple's `Security` framework) for use within CryptoSwift
    /// ```
    /// /// Starting with a SecKey RSA Key
    /// let rsaSecKey:SecKey
    ///
    /// /// Copy the External Representation
    /// var externalRepError:Unmanaged<CFError>?
    /// guard let externalRep = SecKeyCopyExternalRepresentation(rsaSecKey, &externalRepError) as? Data else {
    ///     /// Failed to copy external representation for RSA SecKey
    ///     return
    /// }
    ///
    /// /// Instantiate the RSA Key from the raw external representation
    /// let rsaKey = try RSA(rawRepresentation: externalRep)
    ///
    /// /// You now have a CryptoSwift RSA Key
    /// // rsaKey.encrypt(...)
    /// // rsaKey.decrypt(...)
    /// // rsaKey.sign(...)
    /// // rsaKey.verify(...)
    /// ```
    public convenience init(rawRepresentation raw: Data) throws {
        do { try self.init(privateDER: raw.bytes) } catch {
            try self.init(publicDER: raw.bytes)
        }
    }
}

// MARK: DER Exports (See #892)

extension RSA {
    /// The DER representation of this public key
    ///
    /// [IETF Spec RFC2313](https://datatracker.ietf.org/doc/html/rfc2313#section-7.1)
    /// ```
    /// =========================
    ///  RSA PublicKey Structure
    /// =========================
    ///
    /// RSAPublicKey ::= SEQUENCE {
    ///   modulus           INTEGER,  -- n
    ///   publicExponent    INTEGER   -- e
    /// }
    /// ```
    func publicKeyDER() throws -> [UInt8] {
        let mod = n.serialize()
        let pubKeyAsnNode: ASN1.Node =
            .sequence(nodes: [
                .integer(data: DER.i2ospData(x: mod.bytes, size: keySizeBytes)),
                .integer(data: DER.i2ospData(x: e.serialize().bytes, size: 3)),
            ])
        return ASN1.Encoder.encode(pubKeyAsnNode)
    }

    /// The DER representation of this private key
    ///
    /// [IETF Spec RFC2313](https://datatracker.ietf.org/doc/html/rfc2313#section-7.2)
    /// ```
    /// ==========================
    ///  RSA PrivateKey Structure
    /// ==========================
    ///
    /// RSAPrivateKey ::= SEQUENCE {
    ///   version           Version,
    ///   modulus           INTEGER,  -- n
    ///   publicExponent    INTEGER,  -- e
    ///   privateExponent   INTEGER,  -- d
    ///   prime1            INTEGER,  -- p
    ///   prime2            INTEGER,  -- q
    ///   exponent1         INTEGER,  -- d mod (p-1)
    ///   exponent2         INTEGER,  -- d mod (q-1)
    ///   coefficient       INTEGER,  -- (inverse of q) mod p
    /// }
    /// ```
    func privateKeyDER() throws -> [UInt8] {
        // Make sure we have a private key
        guard let d = d else { throw RSA.Error.noPrivateKey }
        // Make sure we have access to our primes
        guard let primes = primes else { throw RSA.Error.noPrimes }
        // Make sure we can calculate our coefficient (inverse of q mod p)
        guard let coefficient = primes.q.inverse(primes.p) else { throw RSA.Error.unableToCalculateCoefficient }

        let paramWidth = keySizeBytes / 2
        // Structure the data (according to RFC2313, version 0x00 RSA Private Key Syntax)
        let mod = n.serialize()
        let privateKeyAsnNode: ASN1.Node =
            .sequence(nodes: [
                .integer(data: Data(hex: "0x00")),
                .integer(data: DER.i2ospData(x: mod.bytes, size: keySizeBytes)),
                .integer(data: DER.i2ospData(x: e.serialize().bytes, size: 3)),
                .integer(data: DER.i2ospData(x: d.serialize().bytes, size: keySizeBytes)),
                .integer(data: DER.i2ospData(x: primes.p.serialize().bytes, size: paramWidth)),
                .integer(data: DER.i2ospData(x: primes.q.serialize().bytes, size: paramWidth)),
                .integer(data: DER.i2ospData(x: (d % (primes.p - 1)).serialize().bytes, size: paramWidth)),
                .integer(data: DER.i2ospData(x: (d % (primes.q - 1)).serialize().bytes, size: paramWidth)),
                .integer(data: DER.i2ospData(x: coefficient.serialize().bytes, size: paramWidth)),
            ])

        // Encode and return the data
        return ASN1.Encoder.encode(privateKeyAsnNode)
    }

    /// This method returns the DER encoding of the RSA Key.
    ///
    /// - Returns: The ASN1 DER Encoding of the Public or Private RSA Key
    /// - Note: If the RSA Key is a private key, the private key representation is returned
    /// - Note: If the RSA Key is a public key, the public key representation is returned
    /// - Note: If you'd like to only export the public DER of an RSA Key call the `publicKeyExternalRepresentation()` method
    /// - Note: This method returns the same data as Apple's `SecKeyCopyExternalRepresentation` method.
    ///
    /// An example of converting a CryptoSwift RSA key to a SecKey RSA key
    /// ```
    /// /// Starting with a CryptoSwift RSA Key
    /// let rsaKey = try RSA(keySize: 1024)
    ///
    /// /// Define your Keys attributes
    /// let attributes: [String:Any] = [
    ///   kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
    ///   kSecAttrKeyClass as String: kSecAttrKeyClassPrivate, // or kSecAttrKeyClassPublic
    ///   kSecAttrKeySizeInBits as String: 1024, // The appropriate bits
    ///   kSecAttrIsPermanent as String: false
    /// ]
    /// var error:Unmanaged<CFError>? = nil
    /// guard let rsaSecKey = try SecKeyCreateWithData(rsaKey.externalRepresentation() as CFData, attributes as CFDictionary, &error) else {
    ///   /// Error constructing SecKey from raw key data
    ///   return
    /// }
    ///
    /// /// You now have an RSA SecKey for use with Apple's Security framework
    /// ```
    ///
    /// An example of converting a SecKey RSA key to a CryptoSwift RSA key
    /// ```
    /// /// Starting with a SecKey RSA Key
    /// let rsaSecKey:SecKey
    ///
    /// /// Copy External Representation
    /// var externalRepError:Unmanaged<CFError>?
    /// guard let cfdata = SecKeyCopyExternalRepresentation(rsaSecKey, &externalRepError) else {
    ///     /// Failed to copy external representation for RSA SecKey
    ///     return
    /// }
    ///
    /// /// Instantiate the RSA Key from the raw external representation
    /// let rsaKey = try RSA(rawRepresentation: cfdata as Data)
    ///
    /// /// You now have a CryptoSwift RSA Key
    /// ```
    ///
    public func externalRepresentation() throws -> Data {
        if primes != nil {
            return try Data(privateKeyDER())
        } else {
            return try Data(publicKeyDER())
        }
    }

    public func publicKeyExternalRepresentation() throws -> Data {
        return try Data(publicKeyDER())
    }
}

// MARK: CS.BigUInt extension

public extension BigUInteger {
    static func generatePrime(_ width: Int) -> BigUInteger {
        // Note: Need to find a better way to generate prime numbers
        while true {
            var random = BigUInteger.randomInteger(withExactWidth: width)
            random |= BigUInteger(1)
            if random.isPrime() {
                return random
            }
        }
    }
}

// MARK: CustomStringConvertible Conformance

extension RSA: CustomStringConvertible {
    public var description: String {
        if d != nil {
            return "CryptoSwift.RSA.PrivateKey<\(keySize)>"
        } else {
            return "CryptoSwift.RSA.PublicKey<\(keySize)>"
        }
    }
}
