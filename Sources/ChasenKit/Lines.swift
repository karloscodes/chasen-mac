import Foundation

extension FileHandle {
    /// Calls `each` with every line of a pipe as it comes, until the pipe ends.
    ///
    /// Not `bytes.lines`: every `AsyncBytes` of a process reads on one serial
    /// queue, so a pipe that stays silent stops the other pipes. Here each
    /// pipe has a thread of its own.
    public func readLines(_ each: @escaping @Sendable (String) -> Void) {
        Thread.detachNewThread {
            var rest = Data()
            while case let data = self.availableData, !data.isEmpty {
                rest.append(data)
                while let end = rest.firstIndex(of: UInt8(ascii: "\n")) {
                    each(String(decoding: rest[..<end], as: UTF8.self))
                    rest = Data(rest[rest.index(after: end)...])
                }
            }
            if !rest.isEmpty {
                each(String(decoding: rest, as: UTF8.self))
            }
        }
    }
}

extension [String] {
    /// The last lines that a process said, with this one. ssh says the same
    /// lines at each ask: a line that comes again moves to the end.
    public func hearing(_ line: String) -> [String] {
        guard !line.isEmpty else { return self }
        return Array((filter { $0 != line } + [line]).suffix(5))
    }
}
