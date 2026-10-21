import Foundation
import os

/// The lines arriving on a pipe, in order, ending at EOF.
///
/// Fed from the file handle's `readabilityHandler` (a Dispatch source) rather
/// than `FileHandle.bytes`, which parks a Swift concurrency thread in a
/// blocking `read` for as long as the pipe is open. With a reader for the
/// helper's stdout and one for its stderr, a few relaunched (or, in tests,
/// parallel) helpers could tie up the whole cooperative pool and stall every
/// actor in the app.
enum PipeLines {
    static func stream(from handle: FileHandle) -> AsyncStream<String> {
        let (lines, sink) = AsyncStream.makeStream(of: String.self)
        let partial = OSAllocatedUnfairLock(initialState: Data())   // bytes after the last newline
        handle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {   // EOF
                handle.readabilityHandler = nil
                let rest = partial.withLock { buffer in
                    defer { buffer = Data() }
                    return buffer
                }
                if !rest.isEmpty { sink.yield(String(decoding: rest, as: UTF8.self)) }
                sink.finish()
                return
            }
            let complete = partial.withLock { buffer in
                buffer.append(chunk)
                return split(&buffer)
            }
            for line in complete { sink.yield(line) }
        }
        return lines
    }

    /// Remove the complete lines from the front of `buffer`, without their newlines.
    static func split(_ buffer: inout Data) -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }
}
