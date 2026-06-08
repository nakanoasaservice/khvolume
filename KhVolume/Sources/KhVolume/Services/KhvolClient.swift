import Foundation

protocol KhvolClientProtocol: Sendable {
    func jsonStatus() async throws -> KhvolJSONStatus
    func setLevel(_ level: Double) async throws -> KhvolJSONStatus
    func setMuted(_ muted: Bool) async throws -> KhvolJSONStatus
    func interfaces() async throws -> [NetworkInterfaceInfo]
    @discardableResult func scan() async throws -> Int
}

enum KhvolError: LocalizedError {
    case helperMissing
    case commandFailed(String)
    case deviceError(String)
    case parseFailed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "khvol helper not found"
        case .commandFailed(let msg):
            return msg
        case .deviceError(let msg):
            return msg
        case .parseFailed:
            return "Failed to parse khvol output"
        case .timedOut:
            return "khvol timed out"
        }
    }
}

struct KhvolClient {
    let configDir: URL
    let interface: String?

    func run(_ command: [String], timeoutSeconds: TimeInterval = 45) async throws -> String {
        let helper = try resolveHelperURL()
        var extraEnv: [String: String] = [:]
        #if DEBUG
        if !AppPaths.useBundledHelperOnly, let root = devRepoRoot() {
            let helperRoot = root.appendingPathComponent("KhVolume/Helper", isDirectory: true)
            if FileManager.default.fileExists(atPath: helperRoot.appendingPathComponent("khvol_cli.py").path) {
                extraEnv["KHVOL_ROOT"] = helperRoot.path
            }
            let venvPython = root.appendingPathComponent(".venv/bin/python")
            if FileManager.default.fileExists(atPath: venvPython.path) {
                extraEnv["KHVOL_PYTHON"] = venvPython.path
            }
        }
        #endif

        let configuration = KhvolRunConfiguration(
            helperPath: helper.path,
            configDirPath: configDir.path,
            interface: interface,
            command: command,
            extraEnv: extraEnv,
            timeoutSeconds: timeoutSeconds
        )

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try KhvolClient.execute(configuration)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func jsonStatus() async throws -> KhvolJSONStatus {
        try decodeStatusJSON(from: try await run(["json"]))
    }

    func setLevel(_ level: Double) async throws -> KhvolJSONStatus {
        let raw = try await run([
            "set",
            String(format: "%.1f", level),
        ])
        return try decodeStatusJSON(from: raw)
    }

    func setMuted(_ muted: Bool) async throws -> KhvolJSONStatus {
        try decodeStatusJSON(from: try await run([muted ? "mute" : "unmute"]))
    }

    private func decodeStatusJSON(from raw: String) throws -> KhvolJSONStatus {
        guard let data = raw.data(using: .utf8) else { throw KhvolError.parseFailed }
        return try JSONDecoder().decode(KhvolJSONStatus.self, from: data)
    }

    func interfaces() async throws -> [NetworkInterfaceInfo] {
        let raw = try await run(["interfaces"])
        guard let data = raw.data(using: .utf8) else { throw KhvolError.parseFailed }
        return try JSONDecoder().decode([NetworkInterfaceInfo].self, from: data)
    }

    @discardableResult
    func scan() async throws -> Int {
        let raw = try await run(["scan"])
        guard let data = raw.data(using: .utf8) else { throw KhvolError.parseFailed }
        return try JSONDecoder().decode(KhvolScanResult.self, from: data).speakerCount
    }

    private static func execute(_ configuration: KhvolRunConfiguration) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.helperPath)
        process.currentDirectoryURL = URL(fileURLWithPath: configuration.configDirPath, isDirectory: true)

        var args = ["--config-dir", configuration.configDirPath]
        if let interface = configuration.interface, !interface.isEmpty {
            args.append(contentsOf: ["--interface", interface])
        }
        args.append(contentsOf: configuration.command)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var env = ProcessInfo.processInfo.environment
        for (key, value) in configuration.extraEnv {
            env[key] = value
        }
        process.environment = env

        try process.run()

        let waitResult = DispatchTimeout.wait(for: process, seconds: configuration.timeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            throw KhvolError.timedOut
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        switch process.terminationStatus {
        case 0:
            return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        case 2:
            throw KhvolError.deviceError(stderr.isEmpty ? stdout : stderr)
        default:
            throw KhvolError.commandFailed(stderr.isEmpty ? stdout : stderr)
        }
    }

    private func resolveHelperURL() throws -> URL {
        for url in helperCandidateURLs() {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  FileManager.default.isExecutableFile(atPath: url.path)
            else { continue }
            return url
        }
        throw KhvolError.helperMissing
    }

    private func helperCandidateURLs() -> [URL] {
        var urls: [URL] = []
        let bundleURL = Bundle.main.bundleURL

        if let auxiliary = Bundle.main.url(forAuxiliaryExecutable: "khvol") {
            urls.append(auxiliary)
        }

        let helpers = bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        urls.append(helpers.appendingPathComponent("khvol-bundle/khvol"))
        urls.append(helpers.appendingPathComponent("khvol"))

        #if DEBUG
        if !AppPaths.useBundledHelperOnly, let root = devRepoRoot() {
            urls.append(root.appendingPathComponent("KhVolume/Scripts/khvol-dev"))
            urls.append(root.appendingPathComponent("KhVolume/Helpers/khvol"))
        }
        #endif

        return urls
    }

    #if DEBUG
    private func devRepoRoot() -> URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let marker = "KhVolume/Helper/khvol_cli.py"
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent(marker).path) {
            return cwd
        }
        var url = Bundle.main.bundleURL
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(marker).path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
    #endif
}

extension KhvolClient: KhvolClientProtocol {}


private enum DispatchTimeout {
    enum WaitResult {
        case finished
        case timedOut
    }

    static func wait(for process: Process, seconds: TimeInterval) -> WaitResult {
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            group.leave()
        }
        return group.wait(timeout: .now() + seconds) == .success ? .finished : .timedOut
    }
}

private struct KhvolRunConfiguration: Sendable {
    let helperPath: String
    let configDirPath: String
    let interface: String?
    let command: [String]
    let extraEnv: [String: String]
    let timeoutSeconds: TimeInterval
}

private struct KhvolScanResult: Codable {
    let speakerCount: Int
}
