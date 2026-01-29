import Foundation
import CoreImage
import CoreVideo
import CryptoKit
import UIKit

/// Embeds invisible metadata watermarks into video frames
/// Uses spatial-domain LSB watermarking (survives light compression)
/// Encodes: GPS, timestamp, device ID, incident ID, chunk number
class WatermarkService {
    static let shared = WatermarkService()

    // MARK: - Configuration

    struct WatermarkPayload {
        let incidentID: String
        let chunkNumber: Int
        let latitude: Double
        let longitude: Double
        let timestamp: Date
        let deviceID: String

        /// Encode payload as compact binary (64 bytes max)
        func encode() -> Data {
            var data = Data()

            // Magic bytes (2 bytes)
            data.append(contentsOf: [0x4F, 0x54]) // "OT" for OnTheRecord

            // Version (1 byte)
            data.append(0x01)

            // Chunk number (2 bytes, big endian)
            var chunk = UInt16(min(chunkNumber, 65535)).bigEndian
            data.append(Data(bytes: &chunk, count: 2))

            // Timestamp (4 bytes, Unix epoch truncated)
            var ts = UInt32(timestamp.timeIntervalSince1970).bigEndian
            data.append(Data(bytes: &ts, count: 4))

            // Latitude (4 bytes, fixed point: value * 1000000)
            var lat = Int32(latitude * 1_000_000).bigEndian
            data.append(Data(bytes: &lat, count: 4))

            // Longitude (4 bytes, fixed point)
            var lon = Int32(longitude * 1_000_000).bigEndian
            data.append(Data(bytes: &lon, count: 4))

            // Incident ID hash (8 bytes)
            let idHash = SHA256.hash(data: Data(incidentID.utf8))
            data.append(contentsOf: idHash.prefix(8))

            // Device ID hash (4 bytes)
            let devHash = SHA256.hash(data: Data(deviceID.utf8))
            data.append(contentsOf: devHash.prefix(4))

            // CRC16 checksum (2 bytes)
            var crc = crc16(data)
            data.append(Data(bytes: &crc, count: 2))

            return data  // 35 bytes total
        }

        private func crc16(_ data: Data) -> UInt16 {
            var crc: UInt16 = 0xFFFF
            for byte in data {
                crc ^= UInt16(byte)
                for _ in 0..<8 {
                    if crc & 1 != 0 {
                        crc = (crc >> 1) ^ 0xA001
                    } else {
                        crc >>= 1
                    }
                }
            }
            return crc
        }
    }

    // MARK: - Watermark Embedding

    /// Embed watermark into a pixel buffer (modifies in-place)
    /// Uses LSB (Least Significant Bit) embedding in the blue channel
    /// Watermark is spread across multiple pixel rows for redundancy
    func embedWatermark(in pixelBuffer: CVPixelBuffer, payload: WatermarkPayload) {
        let payloadData = payload.encode()
        let payloadBits = dataToBits(payloadData)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        // Only support BGRA format
        guard pixelFormat == kCVPixelFormatType_32BGRA else { return }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Embed in 3 rows for redundancy (top, middle, bottom of frame)
        let rows = [2, height / 2, height - 3]

        for row in rows {
            guard row >= 0 && row < height else { continue }

            for (bitIndex, bit) in payloadBits.enumerated() {
                let col = bitIndex * 4 + 8  // Skip first 8 pixels, space out every 4 pixels
                guard col < width else { break }

                let offset = row * bytesPerRow + col * 4
                guard offset + 3 < height * bytesPerRow else { break }

                // Modify LSB of blue channel (index 0 in BGRA)
                if bit {
                    buffer[offset] |= 0x01       // Set LSB
                } else {
                    buffer[offset] &= 0xFE       // Clear LSB
                }
            }
        }
    }

    /// Extract watermark from a pixel buffer
    func extractWatermark(from pixelBuffer: CVPixelBuffer) -> WatermarkPayload? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Try middle row first (most likely to survive cropping)
        let row = height / 2
        var bits: [Bool] = []

        let expectedBits = 35 * 8  // 35 bytes payload

        for bitIndex in 0..<expectedBits {
            let col = bitIndex * 4 + 8
            guard col < width else { break }

            let offset = row * bytesPerRow + col * 4
            guard offset < height * bytesPerRow else { break }

            bits.append(buffer[offset] & 0x01 != 0)
        }

        guard bits.count == expectedBits else { return nil }

        let data = bitsToData(bits)

        // Verify magic bytes
        guard data.count >= 3, data[0] == 0x4F, data[1] == 0x54, data[2] == 0x01 else {
            return nil
        }

        // Decode payload
        return decodePayload(data)
    }

    // MARK: - Bit Conversion

    private func dataToBits(_ data: Data) -> [Bool] {
        var bits: [Bool] = []
        for byte in data {
            for i in (0..<8).reversed() {
                bits.append((byte >> i) & 1 == 1)
            }
        }
        return bits
    }

    private func bitsToData(_ bits: [Bool]) -> Data {
        var data = Data()
        for i in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 {
                if i + j < bits.count && bits[i + j] {
                    byte |= (1 << (7 - j))
                }
            }
            data.append(byte)
        }
        return data
    }

    private func decodePayload(_ data: Data) -> WatermarkPayload? {
        guard data.count >= 33 else { return nil }  // minimum without CRC

        // Skip magic (2) and version (1)
        let chunkNumber = Int(UInt16(bigEndian: data.subdata(in: 3..<5).withUnsafeBytes { $0.load(as: UInt16.self) }))
        let timestamp = Date(timeIntervalSince1970: TimeInterval(UInt32(bigEndian: data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self) })))
        let latitude = Double(Int32(bigEndian: data.subdata(in: 9..<13).withUnsafeBytes { $0.load(as: Int32.self) })) / 1_000_000
        let longitude = Double(Int32(bigEndian: data.subdata(in: 13..<17).withUnsafeBytes { $0.load(as: Int32.self) })) / 1_000_000

        return WatermarkPayload(
            incidentID: "extracted",  // Can't fully recover from hash
            chunkNumber: chunkNumber,
            latitude: latitude,
            longitude: longitude,
            timestamp: timestamp,
            deviceID: "extracted"
        )
    }
}
