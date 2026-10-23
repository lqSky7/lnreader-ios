// Gzip.swift - Reads .gz data with Apple's Compression framework.

import Compression
import Foundation

enum Gzip {

    enum GzipError: LocalizedError {
        case notGzip
        case truncated
        case corrupt
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .notGzip: "The file is not gzip data."
            case .truncated: "The gzip data ends early."
            case .corrupt: "The gzip data is damaged."
            case .tooLarge: "The file expands to more than the allowed size."
            }
        }
    }

    static func isGzip(_ data: Data) -> Bool {
        data.count >= 3 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    /// Inflate `data`, refusing to produce more than `limit` bytes.
    ///
    /// The cap matters: the size a gzip trailer claims is attacker-controlled,
    /// so the output is bounded while decoding rather than trusted up front.
    static func decompress(_ data: Data, limit: Int) throws -> Data {
        guard isGzip(data), data[data.startIndex + 2] == 8 else { throw GzipError.notGzip }
        let bytes = [UInt8](data)
        let body = try deflateStart(in: bytes)

        var output = Data()
        let chunk = 1 << 16
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { destination.deallocate() }

        // `COMPRESSION_ZLIB` is a raw DEFLATE stream, which is what follows the
        // gzip header.
        var stream = compression_stream(
            dst_ptr: destination, dst_size: 0, src_ptr: destination, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { throw GzipError.corrupt }
        defer { compression_stream_destroy(&stream) }

        return try bytes.withUnsafeBufferPointer { source -> Data in
            stream.src_ptr = source.baseAddress!.advanced(by: body)
            stream.src_size = bytes.count - body

            while true {
                stream.dst_ptr = destination
                stream.dst_size = chunk
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunk - stream.dst_size
                if produced > 0 {
                    guard output.count + produced <= limit else { throw GzipError.tooLarge }
                    output.append(destination, count: produced)
                }
                switch status {
                case COMPRESSION_STATUS_END: return output
                case COMPRESSION_STATUS_OK:
                    // No progress and no input left means the stream was cut short.
                    if produced == 0 && stream.src_size == 0 { throw GzipError.truncated }
                default: throw GzipError.corrupt
                }
            }
        }
    }

    /// Offset of the first DEFLATE byte, after the optional header fields.
    private static func deflateStart(in bytes: [UInt8]) throws -> Int {
        guard bytes.count >= 18 else { throw GzipError.truncated }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {                       // FEXTRA
            guard index + 2 <= bytes.count else { throw GzipError.truncated }
            index += 2 + Int(bytes[index]) + Int(bytes[index + 1]) << 8
        }
        for bit: UInt8 in [0x08, 0x10] where flags & bit != 0 {   // FNAME, FCOMMENT
            while index < bytes.count && bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { index += 2 }          // FHCRC
        guard index < bytes.count else { throw GzipError.truncated }
        return index
    }
}
