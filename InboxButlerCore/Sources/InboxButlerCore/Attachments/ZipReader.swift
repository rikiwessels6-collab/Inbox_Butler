import Foundation
import Compression

/// Minimal ZIP reader, just enough to open .docx files (which are ZIP archives).
/// Reads one named entry; supports "stored" and "deflate". Not a general unzip.
enum ZipReader {
    enum ZipError: Error { case notAZip, entryNotFound, unsupported, tooLarge, corrupt }

    static let maxEntryBytes = 30_000_000   // guards against zip bombs

    static func readEntry(named name: String, from data: Data) throws -> Data {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

        // End-of-central-directory record: signature 0x06054b50, within the last 64KB.
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        var eocd = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 22 - 65_535) {
            if u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let entryCount = u16(eocd + 10)
        var offset = u32(eocd + 16)

        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count, u32(offset) == 0x0201_4b50 else { throw ZipError.corrupt }
            let method = u16(offset + 10)
            let compressedSize = u32(offset + 20)
            let uncompressedSize = u32(offset + 24)
            let nameLength = u16(offset + 28)
            let extraLength = u16(offset + 30)
            let commentLength = u16(offset + 32)
            let localOffset = u32(offset + 42)
            guard offset + 46 + nameLength <= bytes.count else { throw ZipError.corrupt }
            let entryName = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)

            if entryName == name {
                guard uncompressedSize <= maxEntryBytes else { throw ZipError.tooLarge }
                guard localOffset + 30 <= bytes.count, u32(localOffset) == 0x0403_4b50 else { throw ZipError.corrupt }
                let dataStart = localOffset + 30 + u16(localOffset + 26) + u16(localOffset + 28)
                guard dataStart + compressedSize <= bytes.count else { throw ZipError.corrupt }
                let raw = Data(bytes[dataStart..<(dataStart + compressedSize)])
                switch method {
                case 0: return raw
                case 8: return try inflate(raw, expectedSize: uncompressedSize)
                default: throw ZipError.unsupported
                }
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        throw ZipError.entryNotFound
    }

    /// Raw DEFLATE (what ZIP stores) is what Apple's COMPRESSION_ZLIB decodes.
    private static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var out = [UInt8](repeating: 0, count: expectedSize)
        let written = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&out, expectedSize, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { throw ZipError.corrupt }
        return Data(out.prefix(written))
    }
}
