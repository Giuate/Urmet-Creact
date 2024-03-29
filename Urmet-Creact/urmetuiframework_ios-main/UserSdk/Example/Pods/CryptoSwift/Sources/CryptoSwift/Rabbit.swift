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

public final class Rabbit: BlockCipher {
    public enum Error: Swift.Error {
        case invalidKeyOrInitializationVector
    }

    /// Size of IV in bytes
    public static let ivSize = 64 / 8

    /// Size of key in bytes
    public static let keySize = 128 / 8

    /// Size of block in bytes
    public static let blockSize = 128 / 8

    public var keySize: Int {
        key.count
    }

    /// Key
    private let key: Key

    /// IV (optional)
    private let iv: [UInt8]?

    /// State variables
    private var x = [UInt32](repeating: 0, count: 8)

    /// Counter variables
    private var c = [UInt32](repeating: 0, count: 8)

    /// Counter carry
    private var p7: UInt32 = 0

    /// 'a' constants
    private var a: [UInt32] = [
        0x4D34_D34D,
        0xD34D_34D3,
        0x34D3_4D34,
        0x4D34_D34D,
        0xD34D_34D3,
        0x34D3_4D34,
        0x4D34_D34D,
        0xD34D_34D3,
    ]

    // MARK: - Initializers

    public convenience init(key: [UInt8]) throws {
        try self.init(key: key, iv: nil)
    }

    public init(key: [UInt8], iv: [UInt8]?) throws {
        self.key = Key(bytes: key)
        self.iv = iv

        guard key.count == Rabbit.keySize && (iv == nil || iv!.count == Rabbit.ivSize) else {
            throw Error.invalidKeyOrInitializationVector
        }
    }

    // MARK: -

    fileprivate func setup() {
        p7 = 0

        // Key divided into 8 subkeys
        let k = [UInt32](unsafeUninitializedCapacity: 8) { buf, count in
            for j in 0 ..< 8 {
                buf[j] = UInt32(self.key[Rabbit.blockSize - (2 * j + 1)]) | (UInt32(self.key[Rabbit.blockSize - (2 * j + 2)]) << 8)
            }
            count = 8
        }

        // Initialize state and counter variables from subkeys
        for j in 0 ..< 8 {
            if j % 2 == 0 {
                x[j] = (k[(j + 1) % 8] << 16) | k[j]
                c[j] = (k[(j + 4) % 8] << 16) | k[(j + 5) % 8]
            } else {
                x[j] = (k[(j + 5) % 8] << 16) | k[(j + 4) % 8]
                c[j] = (k[j] << 16) | k[(j + 1) % 8]
            }
        }

        // Iterate system four times
        nextState()
        nextState()
        nextState()
        nextState()

        // Reinitialize counter variables
        for j in 0 ..< 8 {
            c[j] = c[j] ^ x[(j + 4) % 8]
        }

        if let iv = iv {
            setupIV(iv)
        }
    }

    private func setupIV(_ iv: [UInt8]) {
        // 63...56 55...48 47...40 39...32 31...24 23...16 15...8 7...0 IV bits
        //    0       1       2       3       4       5       6     7   IV bytes in array
        let iv0 = UInt32(bytes: [iv[4], iv[5], iv[6], iv[7]])
        let iv1 = UInt32(bytes: [iv[0], iv[1], iv[4], iv[5]])
        let iv2 = UInt32(bytes: [iv[0], iv[1], iv[2], iv[3]])
        let iv3 = UInt32(bytes: [iv[2], iv[3], iv[6], iv[7]])

        // Modify the counter state as function of the IV
        c[0] = c[0] ^ iv0
        c[1] = c[1] ^ iv1
        c[2] = c[2] ^ iv2
        c[3] = c[3] ^ iv3
        c[4] = c[4] ^ iv0
        c[5] = c[5] ^ iv1
        c[6] = c[6] ^ iv2
        c[7] = c[7] ^ iv3

        // Iterate system four times
        nextState()
        nextState()
        nextState()
        nextState()
    }

    private func nextState() {
        // Before an iteration the counters are incremented
        var carry = p7
        for j in 0 ..< 8 {
            let prev = c[j]
            c[j] = prev &+ a[j] &+ carry
            carry = prev > c[j] ? 1 : 0 // detect overflow
        }
        p7 = carry // save last carry bit

        // Iteration of the system
        x = [UInt32](unsafeUninitializedCapacity: 8) { newX, count in
            newX[0] = self.g(0) &+ rotateLeft(self.g(7), by: 16) &+ rotateLeft(self.g(6), by: 16)
            newX[1] = self.g(1) &+ rotateLeft(self.g(0), by: 8) &+ self.g(7)
            newX[2] = self.g(2) &+ rotateLeft(self.g(1), by: 16) &+ rotateLeft(self.g(0), by: 16)
            newX[3] = self.g(3) &+ rotateLeft(self.g(2), by: 8) &+ self.g(1)
            newX[4] = self.g(4) &+ rotateLeft(self.g(3), by: 16) &+ rotateLeft(self.g(2), by: 16)
            newX[5] = self.g(5) &+ rotateLeft(self.g(4), by: 8) &+ self.g(3)
            newX[6] = self.g(6) &+ rotateLeft(self.g(5), by: 16) &+ rotateLeft(self.g(4), by: 16)
            newX[7] = self.g(7) &+ rotateLeft(self.g(6), by: 8) &+ self.g(5)
            count = 8
        }
    }

    private func g(_ j: Int) -> UInt32 {
        let sum = x[j] &+ c[j]
        let square = UInt64(sum) * UInt64(sum)
        return UInt32(truncatingIfNeeded: square ^ (square >> 32))
    }

    fileprivate func nextOutput() -> [UInt8] {
        nextState()

        var output16 = [UInt16](repeating: 0, count: Rabbit.blockSize / 2)
        output16[7] = UInt16(truncatingIfNeeded: x[0]) ^ UInt16(truncatingIfNeeded: x[5] >> 16)
        output16[6] = UInt16(truncatingIfNeeded: x[0] >> 16) ^ UInt16(truncatingIfNeeded: x[3])
        output16[5] = UInt16(truncatingIfNeeded: x[2]) ^ UInt16(truncatingIfNeeded: x[7] >> 16)
        output16[4] = UInt16(truncatingIfNeeded: x[2] >> 16) ^ UInt16(truncatingIfNeeded: x[5])
        output16[3] = UInt16(truncatingIfNeeded: x[4]) ^ UInt16(truncatingIfNeeded: x[1] >> 16)
        output16[2] = UInt16(truncatingIfNeeded: x[4] >> 16) ^ UInt16(truncatingIfNeeded: x[7])
        output16[1] = UInt16(truncatingIfNeeded: x[6]) ^ UInt16(truncatingIfNeeded: x[3] >> 16)
        output16[0] = UInt16(truncatingIfNeeded: x[6] >> 16) ^ UInt16(truncatingIfNeeded: x[1])

        var output8 = [UInt8](repeating: 0, count: Rabbit.blockSize)
        for j in 0 ..< output16.count {
            output8[j * 2] = UInt8(truncatingIfNeeded: output16[j] >> 8)
            output8[j * 2 + 1] = UInt8(truncatingIfNeeded: output16[j])
        }
        return output8
    }
}

// MARK: Cipher

extension Rabbit: Cipher {
    public func encrypt(_ bytes: ArraySlice<UInt8>) throws -> [UInt8] {
        setup()

        return [UInt8](unsafeUninitializedCapacity: bytes.count) { result, count in
            var output = self.nextOutput()
            var byteIdx = 0
            var outputIdx = 0
            while byteIdx < bytes.count {
                if outputIdx == Rabbit.blockSize {
                    output = self.nextOutput()
                    outputIdx = 0
                }

                result[byteIdx] = bytes[byteIdx] ^ output[outputIdx]

                byteIdx += 1
                outputIdx += 1
            }
            count = bytes.count
        }
    }

    public func decrypt(_ bytes: ArraySlice<UInt8>) throws -> [UInt8] {
        try encrypt(bytes)
    }
}
