import Foundation

/// How a VM attaches to the network. Default is Tart's shared NAT (no flag).
///
/// `bridged:<iface>` puts the VM directly on the host's LAN — needed on hosts where the
/// default NAT is blocked or mangled (e.g. a Zscaler / corporate proxy that intercepts
/// the NAT subnet). `softnet` is isolated software networking.
///
/// Decodes from a single string in a recipe / config: `nat`, `bridged:en0`,
/// `bridged="Wi-Fi"`, or `softnet`. Use `bridged:list` to make `tart` print the
/// available bridged interfaces.
public enum VMNetwork: Codable, Sendable, Equatable {
    /// Explicitly block every non-public IPv4 range that can contain the vmnet
    /// bridge gateway. Softnet's built-in policy otherwise permits that gateway,
    /// which can expose host services (for example SSH) to an untrusted guest.
    private static let privateIPv4Blocks = "10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.0.0.0/24,192.0.2.0/24,192.168.0.0/16,198.18.0.0/15,198.51.100.0/24,203.0.113.0/24,224.0.0.0/4,240.0.0.0/4"

    case nat
    case bridged(String)
    case softnet

    /// The `tart run` flags for this mode (empty for the NAT default).
    public var tartFlags: [String] {
        switch self {
        case .nat: return []
        case .bridged(let iface): return ["--net-bridged=\(iface)"]
        case .softnet: return ["--net-softnet", "--net-softnet-block=\(Self.privateIPv4Blocks)"]
        }
    }

    /// The `orchard create vm` flags for this mode (empty for the NAT default).
    /// Orchard takes `--net-bridged <iface>` and `--net-softnet` (matching Tart's modes).
    public var orchardFlags: [String] {
        switch self {
        case .nat: return []
        case .bridged(let iface): return ["--net-bridged", iface]
        case .softnet: return ["--net-softnet", "--net-softnet-block", Self.privateIPv4Blocks]
        }
    }

    /// Parse a spec string: `nat`, `bridged:<iface>` / `bridged=<iface>`, or `softnet`.
    public init(spec: String) throws {
        let s = spec.trimmingCharacters(in: .whitespaces)
        let lower = s.lowercased()
        if lower.isEmpty || lower == "nat" { self = .nat; return }
        if lower == "softnet" { self = .softnet; return }
        if lower.hasPrefix("bridged") {
            let parts = s.split(whereSeparator: { $0 == ":" || $0 == "=" }).map(String.init)
            self = .bridged(parts.count >= 2 ? parts[1] : "list")
            return
        }
        throw GraftError("invalid network '\(spec)' — expected nat, bridged:<iface>, or softnet")
    }

    /// Round-trips through the spec string (so recipes/config stay human-readable).
    public var specString: String {
        switch self {
        case .nat: return "nat"
        case .bridged(let iface): return "bridged:\(iface)"
        case .softnet: return "softnet"
        }
    }

    public init(from decoder: Decoder) throws {
        try self.init(spec: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(specString)
    }
}
