import Foundation

struct IconChunk {
    let type: String
    let fileURL: URL
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: ICNSBuilder <png-directory> <output.icns>\n".utf8))
    exit(2)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let chunks = [
    IconChunk(type: "icp4", fileURL: directory.appending(path: "16.png")),
    IconChunk(type: "icp5", fileURL: directory.appending(path: "32.png")),
    IconChunk(type: "icp6", fileURL: directory.appending(path: "64.png")),
    IconChunk(type: "ic07", fileURL: directory.appending(path: "128.png")),
    IconChunk(type: "ic08", fileURL: directory.appending(path: "256.png")),
    IconChunk(type: "ic09", fileURL: directory.appending(path: "512.png")),
    IconChunk(type: "ic10", fileURL: directory.appending(path: "1024.png")),
]

func bigEndianData(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

var encodedChunks = Data()
for chunk in chunks {
    let png = try Data(contentsOf: chunk.fileURL)
    encodedChunks.append(Data(chunk.type.utf8))
    encodedChunks.append(bigEndianData(UInt32(png.count + 8)))
    encodedChunks.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianData(UInt32(encodedChunks.count + 8)))
icns.append(encodedChunks)
try icns.write(to: output, options: .atomic)
