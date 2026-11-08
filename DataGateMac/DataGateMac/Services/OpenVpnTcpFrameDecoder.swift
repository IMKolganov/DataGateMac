import Foundation

/// Reassembles OpenVPN's u16-be length-prefixed TCP stream for the UDP WebSocket proxy.
/// Each returned message contains only complete frames; an unfinished frame stays buffered.
nonisolated struct OpenVpnTcpFrameDecoder {
    enum FrameError: Error {
        case emptyDatagram
    }

    private var buffer = Data()

    mutating func append(_ chunk: Data) throws -> Data {
        buffer.append(chunk)
        var consumed = 0
        while buffer.count - consumed >= 2 {
            let index = buffer.startIndex + consumed
            let length = (Int(buffer[index]) << 8) | Int(buffer[index + 1])
            guard length > 0 else { throw FrameError.emptyDatagram }
            guard buffer.count - consumed >= length + 2 else { break }
            consumed += length + 2
        }
        let completeFrames = Data(buffer.prefix(consumed))
        buffer.removeFirst(consumed)
        return completeFrames
    }
}
