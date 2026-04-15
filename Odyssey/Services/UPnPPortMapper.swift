// Odyssey/Services/UPnPPortMapper.swift
import Darwin
import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.odyssey.app", category: "UPnP")

/// Actor that attempts to open a port on the home router via NAT-PMP (RFC 6886)
/// then UPnP/IGD. On success the public IP:port is stored in `status`.
///
/// Mapping lifetime is 7200 s; a background renew task fires every 3600 s.
actor UPnPPortMapper {

    // MARK: - Public State

    enum MappingStatus: Equatable {
        case idle
        case discovering
        case mapped(externalIP: String, externalPort: Int)
        case failed(String)
    }

    private(set) var status: MappingStatus = .idle

    // MARK: - Private State

    private var renewTask: Task<Void, Never>?
    private var lastMappedPort: Int?
    private var controlURL: URL?

    // MARK: - Mapping Lifetime

    private static let leaseDuration: UInt32 = 7200   // seconds
    private static let renewInterval: UInt64  = 3600  // seconds

    // MARK: - Public API

    /// Try NAT-PMP first; fall back to UPnP. Returns the final status.
    func mapPort(_ internalPort: Int) async -> MappingStatus {
        status = .discovering
        lastMappedPort = internalPort

        // NAT-PMP (faster, simpler)
        if let result = await tryNATPMP(port: internalPort) {
            status = result
            scheduleRenew()
            return result
        }

        // UPnP / IGD
        if let result = await tryUPnP(port: internalPort) {
            status = result
            scheduleRenew()
            return result
        }

        let failed = MappingStatus.failed("Neither UPnP nor NAT-PMP succeeded")
        status = failed
        return failed
    }

    /// Re-run mapPort with the same internal port. Called by the renew timer.
    /// Returns the final status.
    func renewMapping() async -> MappingStatus {
        guard let port = lastMappedPort else { return status }
        logger.info("UPnP: renewing port mapping for port \(port)")
        return await mapPort(port)
    }

    /// Remove the port mapping on shutdown.
    func removeMapping() async {
        guard case .mapped(_, let externalPort) = status,
              let port = lastMappedPort
        else { return }

        renewTask?.cancel()
        renewTask = nil

        // NAT-PMP delete: lifetime = 0
        if let gw = await defaultGateway() {
            await sendNATPMPDelete(gateway: gw, internalPort: port)
        }

        // UPnP delete
        if let url = controlURL {
            let localIP = Self.localIPAddress() ?? "127.0.0.1"
            await sendUPnPDeleteMapping(
                controlURL: url,
                externalPort: externalPort,
                internalPort: port,
                internalClient: localIP
            )
        }

        status = .idle
        logger.info("UPnP: port mapping removed")
    }

    // MARK: - NAT-PMP

    private func tryNATPMP(port: Int) async -> MappingStatus? {
        guard let gateway = await defaultGateway() else {
            logger.debug("NAT-PMP: could not determine default gateway")
            return nil
        }
        logger.info("NAT-PMP: gateway=\(gateway) port=\(port)")

        // 1. Request external IP
        guard let publicIP = await natPMPGetExternalIP(gateway: gateway) else {
            logger.debug("NAT-PMP: external IP request failed")
            return nil
        }

        // 2. Request TCP mapping
        guard let externalPort = await natPMPMapTCP(gateway: gateway, internalPort: port) else {
            logger.debug("NAT-PMP: TCP mapping failed")
            return nil
        }

        logger.info("NAT-PMP: mapped \(port) → \(publicIP):\(externalPort)")
        return .mapped(externalIP: publicIP, externalPort: externalPort)
    }

    /// Send NAT-PMP external-address request (opcode 0). Returns IPv4 string or nil.
    private func natPMPGetExternalIP(gateway: String) async -> String? {
        // Request: 2 bytes (version=0, opcode=0)
        let request = Data([0x00, 0x00])

        guard let responseData = await sendUDPWithTimeout(
            host: gateway, port: 5351,
            data: request,
            expectedMinLength: 12,
            timeoutSeconds: 3
        ) else { return nil }

        guard responseData.count >= 12 else { return nil }
        let resultCode = (UInt16(responseData[2]) << 8) | UInt16(responseData[3])
        guard resultCode == 0 else {
            logger.debug("NAT-PMP: external IP result code \(resultCode)")
            return nil
        }

        // Bytes 8-11: external IPv4
        let a = responseData[8], b = responseData[9]
        let c = responseData[10], d = responseData[11]
        let ip = "\(a).\(b).\(c).\(d)"
        // Sanity: reject 0.0.0.0
        guard ip != "0.0.0.0" else { return nil }
        return ip
    }

    /// Send NAT-PMP TCP mapping request. Returns external port or nil.
    private func natPMPMapTCP(gateway: String, internalPort: Int) async -> Int? {
        var request = Data(count: 12)
        request[0] = 0x00  // version
        request[1] = 0x02  // opcode: TCP mapping
        request[2] = 0x00; request[3] = 0x00  // reserved
        // internal port (big-endian)
        let iPort = UInt16(internalPort)
        request[4] = UInt8((iPort >> 8) & 0xFF)
        request[5] = UInt8(iPort & 0xFF)
        // external port = 0 (any)
        request[6] = 0x00; request[7] = 0x00
        // lifetime = 7200 (big-endian)
        let lifetime = Self.leaseDuration
        request[8]  = UInt8((lifetime >> 24) & 0xFF)
        request[9]  = UInt8((lifetime >> 16) & 0xFF)
        request[10] = UInt8((lifetime >> 8) & 0xFF)
        request[11] = UInt8(lifetime & 0xFF)

        guard let responseData = await sendUDPWithTimeout(
            host: gateway, port: 5351,
            data: request,
            expectedMinLength: 16,
            timeoutSeconds: 3
        ) else { return nil }

        guard responseData.count >= 16 else { return nil }
        let resultCode = (UInt16(responseData[2]) << 8) | UInt16(responseData[3])
        guard resultCode == 0 else {
            logger.debug("NAT-PMP: TCP mapping result code \(resultCode)")
            return nil
        }

        // Bytes 10-11: assigned external port
        let externalPort = Int((UInt16(responseData[10]) << 8) | UInt16(responseData[11]))
        guard externalPort > 0 else { return nil }
        return externalPort
    }

    /// Send NAT-PMP delete (lifetime = 0) for the mapped TCP port.
    private func sendNATPMPDelete(gateway: String, internalPort: Int) async {
        var request = Data(count: 12)
        request[0] = 0x00; request[1] = 0x02
        request[2] = 0x00; request[3] = 0x00
        let iPort = UInt16(internalPort)
        request[4] = UInt8((iPort >> 8) & 0xFF)
        request[5] = UInt8(iPort & 0xFF)
        request[6] = 0x00; request[7] = 0x00
        // lifetime = 0 → delete
        request[8] = 0x00; request[9] = 0x00
        request[10] = 0x00; request[11] = 0x00

        _ = await sendUDPWithTimeout(
            host: gateway, port: 5351,
            data: request,
            expectedMinLength: 1,
            timeoutSeconds: 2
        )
    }

    // MARK: - UPnP / IGD

    private func tryUPnP(port: Int) async -> MappingStatus? {
        // 1. SSDP discovery
        guard let locationURL = await ssdpDiscover() else {
            logger.debug("UPnP: SSDP discovery found no device")
            return nil
        }
        logger.info("UPnP: found device at \(locationURL)")

        // 2. Fetch device description and resolve control URL
        guard let ctrlURL = await fetchControlURL(from: locationURL) else {
            logger.debug("UPnP: could not find control URL in device description")
            return nil
        }
        controlURL = ctrlURL

        // 3. Determine local IP
        guard let localIP = Self.localIPAddress() else {
            logger.debug("UPnP: could not determine local IP")
            return nil
        }

        // 4. Add port mapping
        let added = await sendUPnPAddPortMapping(
            controlURL: ctrlURL,
            externalPort: port,
            internalPort: port,
            internalClient: localIP
        )
        guard added else {
            logger.debug("UPnP: AddPortMapping SOAP call failed")
            return nil
        }

        // 5. Get external IP
        guard let publicIP = await sendUPnPGetExternalIP(controlURL: ctrlURL) else {
            logger.debug("UPnP: GetExternalIPAddress SOAP call failed")
            return nil
        }

        logger.info("UPnP: mapped port \(port) → \(publicIP):\(port)")
        return .mapped(externalIP: publicIP, externalPort: port)
    }

    // MARK: - SSDP

    private func ssdpDiscover() async -> URL? {
        let ssdpMessage =
            "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: 239.255.255.250:1900\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 3\r\n" +
            "ST: urn:schemas-upnp-org:service:WANIPConnection:1\r\n" +
            "\r\n"
        let requestData = Data(ssdpMessage.utf8)

        // Also try WANPPPConnection
        let ssdpMessage2 =
            "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: 239.255.255.250:1900\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 3\r\n" +
            "ST: urn:schemas-upnp-org:service:WANPPPConnection:1\r\n" +
            "\r\n"
        let requestData2 = Data(ssdpMessage2.utf8)

        // Try WANIPConnection first, then WANPPPConnection
        if let data = await sendUDPWithTimeout(
            host: "239.255.255.250", port: 1900,
            data: requestData,
            expectedMinLength: 12,
            timeoutSeconds: 4
        ), let location = Self.parseSSDPLocation(from: data) {
            return URL(string: location)
        }

        if let data = await sendUDPWithTimeout(
            host: "239.255.255.250", port: 1900,
            data: requestData2,
            expectedMinLength: 12,
            timeoutSeconds: 4
        ), let location = Self.parseSSDPLocation(from: data) {
            return URL(string: location)
        }

        return nil
    }

    private static func parseSSDPLocation(from data: Data) -> String? {
        guard let response = String(data: data, encoding: .utf8) else { return nil }
        for line in response.components(separatedBy: "\r\n") {
            let lowered = line.lowercased()
            if lowered.hasPrefix("location:") {
                let value = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    // MARK: - Device Description XML

    private func fetchControlURL(from locationURL: URL) async -> URL? {
        do {
            let (data, _) = try await URLSession.shared.data(from: locationURL)
            guard let xmlString = String(data: data, encoding: .utf8) else { return nil }

            // Simple XML scan for WANIPConnection or WANPPPConnection serviceType + controlURL
            let serviceTypes = ["WANIPConnection", "WANPPPConnection"]
            for serviceType in serviceTypes {
                if let ctrlPath = Self.extractControlURL(from: xmlString, serviceType: serviceType) {
                    // Resolve relative path against the base URL
                    let base = URL(string: "\(locationURL.scheme ?? "http")://\(locationURL.host ?? ""):\(locationURL.port ?? 80)")
                    if ctrlPath.hasPrefix("http") {
                        return URL(string: ctrlPath)
                    } else {
                        return base.flatMap { URL(string: ctrlPath, relativeTo: $0)?.absoluteURL }
                    }
                }
            }
        } catch {
            logger.debug("UPnP: device description fetch failed: \(error.localizedDescription)")
        }
        return nil
    }

    private static func extractControlURL(from xml: String, serviceType: String) -> String? {
        // Find a <service> block containing the serviceType string, then extract controlURL
        // We do a simple string search rather than full XML parsing for robustness.
        guard let serviceRange = xml.range(of: serviceType) else { return nil }

        // Walk backwards to find the opening <service> tag
        guard let serviceTagStart = xml.range(of: "<service>", options: .backwards, range: xml.startIndex..<serviceRange.lowerBound) else { return nil }

        // Walk forwards to find closing </service>
        guard let serviceEnd = xml.range(of: "</service>", range: serviceRange.upperBound..<xml.endIndex) else { return nil }

        let block = String(xml[serviceTagStart.lowerBound..<serviceEnd.upperBound])

        // Extract <controlURL>...</controlURL>
        guard let startTag = block.range(of: "<controlURL>"),
              let endTag = block.range(of: "</controlURL>", range: startTag.upperBound..<block.endIndex) else { return nil }

        let path = String(block[startTag.upperBound..<endTag.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    // MARK: - SOAP Calls

    private func sendUPnPAddPortMapping(
        controlURL: URL,
        externalPort: Int,
        internalPort: Int,
        internalClient: String
    ) async -> Bool {
        let serviceType = "urn:schemas-upnp-org:service:WANIPConnection:1"
        let soapBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:AddPortMapping xmlns:u="\(serviceType)">
              <NewRemoteHost></NewRemoteHost>
              <NewExternalPort>\(externalPort)</NewExternalPort>
              <NewProtocol>TCP</NewProtocol>
              <NewInternalPort>\(internalPort)</NewInternalPort>
              <NewInternalClient>\(internalClient)</NewInternalClient>
              <NewEnabled>1</NewEnabled>
              <NewPortMappingDescription>OdysseyApp</NewPortMappingDescription>
              <NewLeaseDuration>\(Self.leaseDuration)</NewLeaseDuration>
            </u:AddPortMapping>
          </s:Body>
        </s:Envelope>
        """
        let soapAction = "\"\(serviceType)#AddPortMapping\""
        guard let response = await performSOAPRequest(
            controlURL: controlURL,
            soapAction: soapAction,
            body: soapBody
        ) else { return false }

        // HTTP 200 with no fault = success
        return !response.contains("<s:Fault>") && !response.contains("<faultcode>")
    }

    private func sendUPnPGetExternalIP(controlURL: URL) async -> String? {
        let serviceType = "urn:schemas-upnp-org:service:WANIPConnection:1"
        let soapBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetExternalIPAddress xmlns:u="\(serviceType)">
            </u:GetExternalIPAddress>
          </s:Body>
        </s:Envelope>
        """
        let soapAction = "\"\(serviceType)#GetExternalIPAddress\""
        guard let response = await performSOAPRequest(
            controlURL: controlURL,
            soapAction: soapAction,
            body: soapBody
        ) else { return nil }

        return Self.extractXMLValue(from: response, tag: "NewExternalIPAddress")
    }

    private func sendUPnPDeleteMapping(
        controlURL: URL,
        externalPort: Int,
        internalPort: Int,
        internalClient: String
    ) async {
        let serviceType = "urn:schemas-upnp-org:service:WANIPConnection:1"
        let soapBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:DeletePortMapping xmlns:u="\(serviceType)">
              <NewRemoteHost></NewRemoteHost>
              <NewExternalPort>\(externalPort)</NewExternalPort>
              <NewProtocol>TCP</NewProtocol>
            </u:DeletePortMapping>
          </s:Body>
        </s:Envelope>
        """
        let soapAction = "\"\(serviceType)#DeletePortMapping\""
        _ = await performSOAPRequest(controlURL: controlURL, soapAction: soapAction, body: soapBody)
    }

    private func performSOAPRequest(controlURL: URL, soapAction: String, body: String) async -> String? {
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(soapAction, forHTTPHeaderField: "SOAPAction")
        request.setValue(controlURL.host ?? "", forHTTPHeaderField: "HOST")
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResp = response as? HTTPURLResponse
            let statusCode = httpResp?.statusCode ?? 0
            if statusCode >= 200 && statusCode < 300 {
                return String(data: data, encoding: .utf8)
            }
            // Some routers return 500 with a fault in the body — still return the body
            logger.debug("UPnP: SOAP status \(statusCode) for action \(soapAction)")
            return String(data: data, encoding: .utf8)
        } catch {
            logger.debug("UPnP: SOAP request failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func extractXMLValue(from xml: String, tag: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>", range: start.upperBound..<xml.endIndex) else {
            return nil
        }
        let value = String(xml[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - Renew Timer

    private func scheduleRenew() {
        renewTask?.cancel()
        renewTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: Self.renewInterval * 1_000_000_000)
            } catch {
                return  // cancelled
            }
            await self.renewMapping()
        }
    }

    // MARK: - UDP Helper (shared for NAT-PMP and SSDP)

    /// Send a UDP datagram and wait for the first response (or timeout).
    /// Returns the response data, or nil on timeout/error.
    private func sendUDPWithTimeout(
        host: String,
        port: UInt16,
        data: Data,
        expectedMinLength: Int,
        timeoutSeconds: Double
    ) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let state = UDPCallState(continuation: continuation)
            let fetch = UDPFetch(
                host: host, port: port,
                data: data,
                expectedMinLength: expectedMinLength,
                timeoutSeconds: timeoutSeconds,
                state: state
            )
            fetch.start()
        }
    }

    // MARK: - Default Gateway

    private func defaultGateway() async -> String? {
        // Run: /sbin/route -n get default
        // Parse "gateway: <ip>" from output
        do {
            let output = try await runProcess(
                executable: "/sbin/route",
                arguments: ["-n", "get", "default"]
            )
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("gateway:") {
                    let gw = trimmed.dropFirst("gateway:".count).trimmingCharacters(in: .whitespaces)
                    if !gw.isEmpty { return gw }
                }
            }
        } catch {
            logger.debug("UPnP: route lookup failed: \(error.localizedDescription)")
        }
        return nil
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Local IP

    static func localIPAddress() -> String? {
        // Prefer en0 (WiFi), then Ethernet adapters
        let priority = ["en0", "en1", "en2", "en3", "en4"]
        var found: [String: String] = [:]
        var other: String? = nil

        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var current = ifaddr
        while let ptr = current {
            let ifa = ptr.pointee
            if ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               let name = String(validatingCString: ifa.ifa_name),
               !name.hasPrefix("lo"), !name.hasPrefix("utun"), !name.hasPrefix("ipsec") {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len),
                    &hostname, socklen_t(hostname.count),
                    nil, 0, NI_NUMERICHOST
                )
                let ip = String(cString: hostname)
                if priority.contains(name) {
                    found[name] = ip
                } else if other == nil {
                    other = ip
                }
            }
            current = ifa.ifa_next
        }

        for iface in priority {
            if let ip = found[iface] { return ip }
        }
        return other
    }
}

// MARK: - UDPFetch (NWConnection-based one-shot UDP exchange)

/// Thread-safe state for a single UDP request/response exchange.
private final class UDPCallState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<Data?, Never>

    init(continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = continuation
    }

    func complete(with data: Data?, conn: NWConnection) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        guard shouldResume else { return }
        conn.cancel()
        continuation.resume(returning: data)
    }
}

private final class UDPFetch: @unchecked Sendable {
    private let conn: NWConnection
    private let state: UDPCallState
    private let requestData: Data
    private let expectedMinLength: Int
    private let queue = DispatchQueue(label: "com.odyssey.p2p.udp")

    init(
        host: String,
        port: UInt16,
        data: Data,
        expectedMinLength: Int,
        timeoutSeconds: Double,
        state: UDPCallState
    ) {
        let params = NWParameters.udp
        self.conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .any,
            using: params
        )
        self.requestData = data
        self.expectedMinLength = expectedMinLength
        self.state = state

        let s = state
        let c = conn
        let q = queue
        q.asyncAfter(deadline: .now() + timeoutSeconds) {
            s.complete(with: nil, conn: c)
        }
    }

    func start() {
        let s = state
        let c = conn
        let req = requestData
        let minLen = expectedMinLength

        conn.stateUpdateHandler = { connState in
            switch connState {
            case .ready:
                c.send(content: req, completion: .contentProcessed { err in
                    if let err {
                        logger.debug("UDPFetch send error: \(err.localizedDescription)")
                        s.complete(with: nil, conn: c)
                        return
                    }
                    c.receive(minimumIncompleteLength: minLen, maximumLength: 512) { data, _, _, error in
                        if let error {
                            logger.debug("UDPFetch receive error: \(error.localizedDescription)")
                            s.complete(with: nil, conn: c)
                        } else {
                            s.complete(with: data, conn: c)
                        }
                    }
                })
            case .failed(let err):
                logger.debug("UDPFetch connection failed: \(err.localizedDescription)")
                s.complete(with: nil, conn: c)
            default:
                break
            }
        }

        conn.start(queue: queue)
    }
}
