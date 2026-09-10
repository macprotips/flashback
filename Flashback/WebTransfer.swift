// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

enum WebAddress {
    static func parse(_ text: String) throws -> URL {
        var value = text.trimmingCharacters(in:.whitespacesAndNewlines)
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string:value) else { throw LibraryError("Enter the address of a game page or game file.") }
        return try checked(url)
    }

    static func checked(_ url: URL, allowLocal: Bool = false) throws -> URL {
        guard var parts = URLComponents(url:url, resolvingAgainstBaseURL:true),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, url.absoluteString.count <= 8192 else {
            throw LibraryError("Use a public HTTP or HTTPS address without a username or password.")
        }
        if !allowLocal {
            let host = host.trimmingCharacters(in:CharacterSet(charactersIn:"[]"))
            guard host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local"),
                  host.contains(".") || host.contains(":"), !isPrivateLiteral(host) else {
                throw LibraryError("Website imports can’t access this Mac or private network addresses.")
            }
        }
        parts.scheme = scheme; parts.host = host; parts.fragment = nil
        if parts.path.isEmpty { parts.path = "/" }
        guard let normalized = parts.url else { throw LibraryError("This web address could not be read.") }
        return normalized
    }

    static func resolve(_ raw: String, from base: URL) -> URL? {
        let value = raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("#"), let url = URL(string:value, relativeTo:base)?.absoluteURL else { return nil }
        // Private addresses are rejected at the network boundary as well.
        return try? checked(url, allowLocal:true)
    }

    static func directory(_ url: URL) -> URL {
        var parts = URLComponents(url:url,resolvingAgainstBaseURL:true)!
        if !parts.path.hasSuffix("/") { parts.path += "/" }
        parts.query = nil; parts.fragment = nil
        return parts.url!
    }

    static func isPrivateLiteral(_ host: String) -> Bool {
        let host = String(host.split(separator:"%",maxSplits:1).first ?? Substring(host))
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, host, &v4) == 1 { return privateIPv4(UInt32(bigEndian:v4.s_addr)) }
        if inet_pton(AF_INET6, host, &v6) == 1 {
            return withUnsafeBytes(of:v6) { bytes in
                let b = Array(bytes)
                if b.prefix(12).allSatisfy({ $0 == 0 }) {
                    return privateIPv4(b.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
                }
                if b.prefix(10).allSatisfy({ $0 == 0 }), b[10] == 255, b[11] == 255 {
                    return privateIPv4(b.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
                }
                return b.prefix(15).allSatisfy({ $0 == 0 }) || b[0] & 0xfe == 0xfc ||
                    (b[0] == 0xfe && b[1] & 0xc0 == 0x80) || b[0] == 0xff
            }
        }
        return false
    }

    private static func privateIPv4(_ value: UInt32) -> Bool {
        let a = value >> 24, b = (value >> 16) & 255
        return a == 0 || a == 10 || a == 127 || a >= 224 ||
            (a == 169 && b == 254) || (a == 172 && (16...31).contains(b)) ||
            (a == 192 && b == 168) || (a == 100 && (64...127).contains(b)) ||
            (a == 198 && (b == 18 || b == 19))
    }

    static func validateNetwork(_ url: URL, allowLocal: Bool) async throws {
        _ = try checked(url, allowLocal:allowLocal)
        if allowLocal { return }
        let host = url.host!.trimmingCharacters(in:CharacterSet(charactersIn:"[]"))
        try await Task.detached(priority:.utility) {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
            var addresses: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &addresses) == 0, let first = addresses else {
                throw LibraryError("The server \(host) could not be found.")
            }
            defer { freeaddrinfo(first) }
            var cursor: UnsafeMutablePointer<addrinfo>? = first
            while let current = cursor {
                var name = [CChar](repeating:0,count:Int(NI_MAXHOST))
                if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0,
                   isPrivateLiteral(String(cString:name)) {
                    throw LibraryError("This address resolves to a private network. Website imports use public servers only.")
                }
                cursor = current.pointee.ai_next
            }
        }.value
        try Task.checkCancellation()
    }
}

struct WebDownload: Sendable {
    let requestedURL: URL
    let url: URL
    let file: URL
    let mimeType: String
    let filename: String
    let bytes: Int64
    let binaryReferenceOnly: Bool
}

/// A streamed, cancellable transfer. Every response and redirect has a budget.
final class WebTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var session: URLSession?
    private var continuation: CheckedContinuation<WebDownload, Error>?
    private var handle: FileHandle?
    private var failure: Error?
    private var response: HTTPURLResponse?
    private var received: Int64 = 0
    private var lastProgress = -Double.infinity
    private var redirects = 0
    private var binaryReferenceOnly = false
    let url: URL
    let file: URL
    let limit: Int64
    let scanOnly: Bool
    let allowLocal: Bool
    let progress: @Sendable (Int64, Int64?) -> Void

    init(url: URL, directory: URL, limit: Int64, scanOnly: Bool, allowLocal: Bool,
         progress: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.url = url; file = directory.appendingPathComponent(UUID().uuidString)
        self.limit = limit; self.scanOnly = scanOnly; self.allowLocal = allowLocal; self.progress = progress
    }

    func start(referer: URL? = nil) async throws -> WebDownload {
        try await WebAddress.validateNetwork(url, allowLocal:allowLocal)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                do {
                    try FileManager.default.createDirectory(at:file.deletingLastPathComponent(), withIntermediateDirectories:true)
                    FileManager.default.createFile(atPath:file.path, contents:nil)
                    handle = try FileHandle(forWritingTo:file)
                    self.continuation = continuation
                    let config = URLSessionConfiguration.ephemeral
                    config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 180
                    config.urlCredentialStorage = nil; config.httpCookieStorage = nil
                    config.httpShouldSetCookies = false; config.requestCachePolicy = .reloadIgnoringLocalCacheData
                    config.httpMaximumConnectionsPerHost = 4
                    session = URLSession(configuration:config, delegate:self, delegateQueue:nil)
                    var request = URLRequest(url:url)
                    request.setValue("Flashback/1.4 (Mac game importer)",forHTTPHeaderField:"User-Agent")
                    request.setValue("*/*",forHTTPHeaderField:"Accept")
                    if let referer {
                        let sameOrigin = referer.scheme == url.scheme && referer.host == url.host && referer.port == url.port
                        if !(referer.scheme == "https" && url.scheme == "http") {
                            let value = sameOrigin ? referer.absoluteString : URLComponents(url:referer,resolvingAgainstBaseURL:true).map { parts in
                                var origin = parts; origin.path = "/"; origin.query = nil; origin.fragment = nil
                                return origin.url?.absoluteString ?? ""
                            } ?? ""
                            request.setValue(value,forHTTPHeaderField:"Referer")
                        }
                    }
                    let newTask = session!.dataTask(with:request)
                    lock.lock(); task = newTask; let stopped = cancelled; lock.unlock()
                    if stopped { newTask.cancel() }
                    newTask.resume()
                } catch { try? handle?.close(); continuation.resume(throwing:error) }
            }
        } onCancel: { self.cancel() }
    }

    func cancel() {
        lock.lock(); cancelled = true; let current = task; lock.unlock()
        current?.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 8, let destination = request.url else {
            failure = LibraryError("This download redirected too many times."); completionHandler(nil); task.cancel(); return
        }
        Task {
            do {
                try await WebAddress.validateNetwork(destination, allowLocal:allowLocal)
                // Never forward authentication or a site's cookie to another host.
                var clean = request
                clean.setValue(nil,forHTTPHeaderField:"Authorization"); clean.setValue(nil,forHTTPHeaderField:"Cookie")
                if response.url?.host != destination.host || response.url?.scheme != destination.scheme { clean.setValue(nil,forHTTPHeaderField:"Referer") }
                completionHandler(clean)
            } catch {
                // URLSession's delegate queue is serial; return state changes there.
                session.delegateQueue.addOperation { self.failure = error; completionHandler(nil); task.cancel() }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling,nil)
        } else {
            failure = LibraryError("This file requires a sign-in. Import a game download you can access directly.")
            completionHandler(.cancelAuthenticationChallenge,nil)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            failure = LibraryError("The server returned an unreadable response."); completionHandler(.cancel); return
        }
        self.response = response
        guard (200...299).contains(response.statusCode) else {
            let explanation = [401:"requires a sign-in",403:"doesn’t allow this download",404:"no longer has this file",410:"has removed this file",429:"is receiving too many requests"]
            failure = LibraryError("The server \(explanation[response.statusCode] ?? "returned HTTP \(response.statusCode)").")
            completionHandler(.cancel); return
        }
        if scanOnly, WebPage.gameExtension(url:response.url!, mime:response.mimeType ?? "", filename:response.suggestedFilename) != nil {
            binaryReferenceOnly = true; completionHandler(.cancel); return
        }
        guard response.expectedContentLength <= limit else {
            failure = LibraryError("This file exceeds the \(ByteCountFormatter.string(fromByteCount:limit,countStyle:.file)) download limit.")
            completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received += Int64(data.count)
        guard received <= limit else {
            failure = LibraryError("This file grew beyond the download limit."); dataTask.cancel(); return
        }
        do { try handle?.write(contentsOf:data) }
        catch { failure = error; dataTask.cancel(); return }
        let total = response?.expectedContentLength ?? -1
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastProgress >= 0.1 || received == total { lastProgress = now; progress(received,total > 0 ? total : nil) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close(); handle = nil
        let pending = continuation; continuation = nil
        defer {
            session.finishTasksAndInvalidate(); self.session = nil
            lock.lock(); self.task = nil; lock.unlock()
        }
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped || failure != nil || (error != nil && !binaryReferenceOnly) || response == nil {
            try? FileManager.default.removeItem(at:file)
            pending?.resume(throwing:stopped ? CancellationError() : (failure ?? error ?? LibraryError("The download did not finish.")))
        } else if let response {
            pending?.resume(returning:WebDownload(requestedURL:url,url:response.url ?? url,file:file,
                mimeType:response.mimeType ?? "",filename:response.suggestedFilename ?? url.lastPathComponent,
                bytes:received,binaryReferenceOnly:binaryReferenceOnly))
        }
    }
}
