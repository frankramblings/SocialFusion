import Foundation

// MARK: - Capability Support Level

/// Level of support for a search capability
public enum CapabilitySupport: String, Codable {
  case unknown = "unknown"
  case likely = "likely"
  case likelyNo = "likelyNo"
  case yes = "yes"
  case no = "no"
  
  public var displayName: String {
    switch self {
    case .unknown: return "Unknown"
    case .likely: return "Likely"
    case .likelyNo: return "Likely Not"
    case .yes: return "Yes"
    case .no: return "No"
    }
  }
  
  public var isSupported: Bool {
    switch self {
    case .yes, .likely: return true
    case .no, .likelyNo, .unknown: return false
    }
  }
}

// MARK: - Search Capabilities

/// Capabilities of a Mastodon instance for search
public struct SearchCapabilities: Codable {
  public var supportsAccountSearch: CapabilitySupport
  public var supportsHashtagSearch: CapabilitySupport
  public var supportsStatusSearch: CapabilitySupport
  public var supportsTrends: Bool
  public var instanceDomain: String?
  public var lastChecked: Date?
  
  public init(
    supportsAccountSearch: CapabilitySupport = .unknown,
    supportsHashtagSearch: CapabilitySupport = .unknown,
    supportsStatusSearch: CapabilitySupport = .unknown,
    supportsTrends: Bool = false,
    instanceDomain: String? = nil,
    lastChecked: Date? = nil
  ) {
    self.supportsAccountSearch = supportsAccountSearch
    self.supportsHashtagSearch = supportsHashtagSearch
    self.supportsStatusSearch = supportsStatusSearch
    self.supportsTrends = supportsTrends
    self.instanceDomain = instanceDomain
    self.lastChecked = lastChecked
  }
  
  /// Update capability based on search results
  public mutating func updateFromSearchResults(
    scope: SearchScope,
    hasResults: Bool,
    hasOtherResults: Bool
  ) {
    switch scope {
    case .posts:
      if hasResults {
        supportsStatusSearch = .yes
      } else if hasOtherResults {
        // Other scopes work but posts don't - likely not supported
        supportsStatusSearch = .likelyNo
      }
    case .users:
      if hasResults {
        supportsAccountSearch = .yes
      } else {
        supportsAccountSearch = .no
      }
    case .tags:
      if hasResults {
        supportsHashtagSearch = .yes
      } else {
        supportsHashtagSearch = .no
      }
    }
    lastChecked = Date()
  }
  
  /// Check if status search is likely not supported
  public var shouldShowStatusSearchWarning: Bool {
    supportsStatusSearch == .likelyNo || supportsStatusSearch == .no
  }
}

// MARK: - Search Capabilities Storage

/// Manages persistence of search capabilities per account
public class SearchCapabilitiesStorage {
  public static let shared = SearchCapabilitiesStorage()
  
  private let userDefaults = UserDefaults.standard
  private let capabilitiesKeyPrefix = "searchCapabilities_"
  
  private init() {}
  
  /// Get capabilities for an account
  public func getCapabilities(for accountId: String) -> SearchCapabilities {
    let key = capabilitiesKeyPrefix + accountId
    guard let data = userDefaults.data(forKey: key),
          let capabilities = try? JSONDecoder().decode(SearchCapabilities.self, from: data) else {
      return SearchCapabilities()
    }
    return capabilities
  }
  
  /// Save capabilities for an account
  public func saveCapabilities(_ capabilities: SearchCapabilities, for accountId: String) {
    let key = capabilitiesKeyPrefix + accountId
    if let data = try? JSONEncoder().encode(capabilities) {
      userDefaults.set(data, forKey: key)
    }
  }
  
  /// Update capabilities based on search results
  public func updateCapabilities(
    for accountId: String,
    scope: SearchScope,
    hasResults: Bool,
    hasOtherResults: Bool
  ) {
    var capabilities = getCapabilities(for: accountId)
    capabilities.updateFromSearchResults(
      scope: scope,
      hasResults: hasResults,
      hasOtherResults: hasOtherResults
    )
    saveCapabilities(capabilities, for: accountId)
  }
}
