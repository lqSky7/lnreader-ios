import Foundation
import Compression

/// A lightweight, self-contained ZIP reader using Apple's built-in Compression framework.
final class MiniZIP {
    struct Entry {
        let path: String
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }
    
    private let data: Data
    private(set) var entries: [String: Entry] = [:]
    
    init?(data: Data) {
        self.data = data
        guard parse() else { return nil }
    }
    
    private func parse() -> Bool {
        let size = data.count
        print("🔍 [MiniZIP] Parsing zip archive of size \(size) bytes...")
        guard size >= 22 else {
            print("❌ [MiniZIP] Archive is too small (\(size) bytes)")
            return false
        }
        var eocdOffset: Int?
        
        // Scan backwards from end of data to find the EOCD signature (0x06054b50)
        let maxScan = min(size, 65535 + 22)
        for i in 22...maxScan {
            let offset = size - i
            let sig = data.readUInt32(at: offset)
            if sig == 0x06054b50 {
                eocdOffset = offset
                break
            }
        }
        
        guard let eocd = eocdOffset else {
            print("❌ [MiniZIP] Failed to find End of Central Directory (EOCD) signature.")
            return false
        }
        
        let cdEntries = data.readUInt16(at: eocd + 10)
        let cdSize = data.readUInt32(at: eocd + 12)
        let cdOffset = data.readUInt32(at: eocd + 16)
        print("🔍 [MiniZIP] Found EOCD at offset \(eocd). Entries count: \(cdEntries), CD Size: \(cdSize) bytes, CD Offset: \(cdOffset)")
        
        var currentOffset = Int(cdOffset)
        for i in 0..<cdEntries {
            guard currentOffset + 46 <= size else {
                print("❌ [MiniZIP] Central directory parsed past end of data at entry \(i)")
                break
            }
            let sig = data.readUInt32(at: currentOffset)
            guard sig == 0x02014b50 else {
                print("❌ [MiniZIP] Invalid CD entry signature: \(String(format: "0x%08X", sig)) at offset \(currentOffset) for entry index \(i)")
                break
            }
            
            let compressionMethod = data.readUInt16(at: currentOffset + 10)
            let compressedSize = data.readUInt32(at: currentOffset + 20)
            let uncompressedSize = data.readUInt32(at: currentOffset + 24)
            let filenameLength = data.readUInt16(at: currentOffset + 28)
            let extraLength = data.readUInt16(at: currentOffset + 30)
            let commentLength = data.readUInt16(at: currentOffset + 32)
            let localOffset = data.readUInt32(at: currentOffset + 42)
            
            let nameStart = currentOffset + 46
            let nameEnd = nameStart + Int(filenameLength)
            guard nameEnd <= size else {
                print("❌ [MiniZIP] Entry name ends out of bounds at offset \(nameEnd)")
                break
            }
            
            let nameData = data.subdata(in: nameStart..<nameEnd)
            if let name = String(data: nameData, encoding: .utf8) {
                let entry = Entry(
                    path: name,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset
                )
                entries[name] = entry
                print("🔍 [MiniZIP]   Parsed file: \"\(name)\" (Method: \(compressionMethod), Size: \(uncompressedSize) bytes, Compressed: \(compressedSize) bytes)")
            } else {
                print("⚠️ [MiniZIP] Entry index \(i) has invalid filename encoding")
            }
            
            currentOffset = nameEnd + Int(extraLength) + Int(commentLength)
        }
        
        print("🔍 [MiniZIP] Successfully parsed \(entries.count) entry records.")
        return true
    }
    
    func fileData(for path: String) -> Data? {
        guard let entry = entries[path] else {
            print("❌ [MiniZIP] File not found in archive entries: \"\(path)\"")
            return nil
        }
        let localOffset = Int(entry.localHeaderOffset)
        guard localOffset + 30 <= data.count else {
            print("❌ [MiniZIP] Local file header offset out of bounds for \"\(path)\"")
            return nil
        }
        
        let sig = data.readUInt32(at: localOffset)
        guard sig == 0x04034b50 else {
            print("❌ [MiniZIP] Invalid local file header signature for \"\(path)\": \(String(format: "0x%08X", sig)) at offset \(localOffset)")
            return nil
        }
        
        let filenameLength = data.readUInt16(at: localOffset + 26)
        let extraLength = data.readUInt16(at: localOffset + 28)
        let dataStart = localOffset + 30 + Int(filenameLength) + Int(extraLength)
        let dataEnd = dataStart + Int(entry.compressedSize)
        
        guard dataEnd <= data.count else {
            print("❌ [MiniZIP] Compressed data ends out of bounds for \"\(path)\"")
            return nil
        }
        let rawData = data.subdata(in: dataStart..<dataEnd)
        
        if entry.compressionMethod == 0 {
            print("🔍 [MiniZIP] Extracting stored file \"\(path)\" (\(entry.uncompressedSize) bytes)")
            return rawData
        } else if entry.compressionMethod == 8 {
            print("🔍 [MiniZIP] Decompressing file \"\(path)\" (Compressed: \(entry.compressedSize) -> Uncompressed: \(entry.uncompressedSize) bytes)")
            let decompressed = decompressDeflate(compressedData: rawData, uncompressedSize: Int(entry.uncompressedSize))
            if decompressed == nil {
                print("❌ [MiniZIP] Failed to decompress file \"\(path)\"")
            }
            return decompressed
        }
        
        print("❌ [MiniZIP] Unsupported compression method \(entry.compressionMethod) for file \"\(path)\"")
        return nil
    }
    
    private func decompressDeflate(compressedData: Data, uncompressedSize: Int) -> Data? {
        if uncompressedSize == 0 { return Data() }
        
        var destinationBuffer = Data(count: uncompressedSize)
        let decodedSize = decompress(compressedData: compressedData, uncompressedSize: uncompressedSize, algorithm: COMPRESSION_ZLIB, into: &destinationBuffer)
        
        if decodedSize == uncompressedSize {
            return destinationBuffer
        }
        
        print("❌ [MiniZIP] Decompression failed under DEFLATE (COMPRESSION_ZLIB) algorithm. Decoded size: \(decodedSize), expected: \(uncompressedSize)")
        return nil
    }
    
    private func decompress(compressedData: Data, uncompressedSize: Int, algorithm: compression_algorithm, into destinationBuffer: inout Data) -> Int {
        destinationBuffer.withUnsafeMutableBytes { (destBytes: UnsafeMutableRawBufferPointer) -> Int in
            compressedData.withUnsafeBytes { (srcBytes: UnsafeRawBufferPointer) -> Int in
                guard let destAddress = destBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let srcAddress = srcBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return compression_decode_buffer(
                    destAddress,
                    uncompressedSize,
                    srcAddress,
                    compressedData.count,
                    nil,
                    algorithm
                )
            }
        }
    }
}

fileprivate extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) |
               (UInt32(self[offset + 1]) << 8) |
               (UInt32(self[offset + 2]) << 16) |
               (UInt32(self[offset + 3]) << 24)
    }
    
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) |
               (UInt16(self[offset + 1]) << 8)
    }
}
