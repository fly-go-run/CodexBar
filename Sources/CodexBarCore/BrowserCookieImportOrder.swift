import SweetCookieKit

public typealias BrowserCookieImportOrder = [Browser]

extension [Browser] {
    /// Filters a browser list to sources worth attempting for cookie imports.
    ///
    /// This is intentionally stricter than "app installed": it aims to avoid unnecessary Keychain prompts.
    public func cookieImportCandidates(using detection: BrowserDetection) -> [Browser] {
        Array(self.lazyCookieImportCandidates(using: detection))
    }

    /// Lazily filters browser sources so callers can stop after the first successful cookie import.
    func lazyCookieImportCandidates(using detection: BrowserDetection) -> some Sequence<Browser> {
        self.lazy.filter { browser in
            if KeychainAccessGate.isDisabled, browser.usesKeychainForCookieDecryption {
                if KeychainAccessGate.isExplicitlyDisabled {
                    BrowserCookieAccessGate.recordAccessFailure(for: browser)
                }
                return false
            }
            let available = detection.isCookieSourceAvailable(browser)
            if !available, detection.cookieSourceProfileAccessIssue(browser) == .accessDenied {
                BrowserCookieAccessGate.recordAccessFailure(for: browser, profileDenied: true)
            }
            return available && BrowserCookieAccessGate.shouldAttempt(browser)
        }
    }

    /// Filters a browser list to sources with usable profile data on disk.
    public func browsersWithProfileData(using detection: BrowserDetection) -> [Browser] {
        self.filter { detection.hasUsableProfileData($0) }
    }
}

extension Browser {
    var usesKeychainForCookieDecryption: Bool {
        self != .safari && !self.usesGeckoProfileStore
    }
}
