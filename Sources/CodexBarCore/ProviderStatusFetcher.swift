import Foundation

private enum StatusFeedDateParser {
    static func decodingStrategy() -> JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601DateParser.parse(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
            }
            return date
        }
    }
}

package enum ProviderStatusFetcher {
    /// Status feeds decode off the main actor: large payloads can cost 150-340ms to decode (#1399),
    /// and these helpers touch no store state.
    @concurrent
    package static func fetchStatus(
        from baseURL: URL,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared)
        async throws -> ProviderStatus
    {
        let apiURL = baseURL.appendingPathComponent("api/v2/status.json")
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10

        let (data, _) = try await transport.data(for: request)

        return try Self.parseStatuspageStatus(data: data)
    }

    /// Resolves the provider's status and component list.
    ///
    /// OpenAI's status page is powered by incident.io, whose native feed groups components
    /// (APIs / ChatGPT / Codex / FedRAMP) — so we try that first. Classic Atlassian
    /// statuspage.io pages (Claude, Cursor, GitHub) expose a flat `api/v2` feed, which we fall
    /// back to. `components.json` is used for the flat list because `summary.json` omits unlisted
    /// components such as "FedRAMP".
    @concurrent
    package static func fetchStatusSummary(
        from baseURL: URL,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared)
        async throws -> (status: ProviderStatus, components: [ProviderStatusComponent]?)
    {
        // incident.io native feed (grouped): https://<host>/proxy/<host>
        if let host = baseURL.host,
           let proxyURL = URL(string: "https://\(host)/proxy/\(host)")
        {
            var proxyRequest = URLRequest(url: proxyURL)
            proxyRequest.timeoutInterval = 10
            if let (data, _) = try? await transport.data(for: proxyRequest),
               let parsed = try? Self.parseIncidentIOSummary(data: data)
            {
                // The proxy feed derives the indicator from component leaves but carries no
                // top-level description or timestamp; fetch the summary endpoint so callers
                // get the full status banner.
                let overlay = try? await Self.fetchStatus(from: baseURL, transport: transport)
                let status = ProviderStatus(
                    indicator: parsed.status.indicator,
                    description: overlay?.description,
                    updatedAt: overlay?.updatedAt)
                return (status, parsed.components)
            }
        }

        // Classic statuspage.io fallback.
        var summaryRequest = URLRequest(url: baseURL.appendingPathComponent("api/v2/summary.json"))
        summaryRequest.timeoutInterval = 10
        var componentsRequest = URLRequest(url: baseURL.appendingPathComponent("api/v2/components.json"))
        componentsRequest.timeoutInterval = 10

        let (summaryData, _) = try await transport.data(for: summaryRequest)
        let status = try Self.parseStatuspageStatus(data: summaryData)
        let components: [ProviderStatusComponent]? = if let (componentsData, _) = try? await transport
            .data(for: componentsRequest)
        {
            try? Self.parseStatuspageComponents(data: componentsData)
        } else {
            nil
        }
        return (status, components)
    }

    /// Parses incident.io's native status-page summary (`/proxy/<host>`). Groups come from
    /// `structure.items`; per-component statuses come from `affected_components` (anything not
    /// listed there is operational). A group's status aggregates the worst of its children.
    package static func parseIncidentIOSummary(
        data: Data)
        throws -> (status: ProviderStatus, components: [ProviderStatusComponent])
    {
        // The incident.io payload mirrors a deeply nested JSON shape; the response models follow it
        // 1:1 for clarity, which exceeds the default type-nesting depth.
        // swiftlint:disable nesting
        struct Response: Decodable {
            struct Summary: Decodable {
                struct AffectedComponent: Decodable {
                    let componentID: String
                    let status: String?
                    private enum CodingKeys: String, CodingKey {
                        case componentID = "component_id"
                        case status
                    }
                }

                struct Structure: Decodable {
                    struct Item: Decodable {
                        struct Group: Decodable {
                            struct Child: Decodable {
                                let componentID: String
                                let name: String?
                                let hidden: Bool?
                                private enum CodingKeys: String, CodingKey {
                                    case componentID = "component_id"
                                    case name, hidden
                                }
                            }

                            let id: String
                            let name: String?
                            let hidden: Bool?
                            let components: [Child]?
                        }

                        struct Component: Decodable {
                            let componentID: String
                            let name: String?
                            let hidden: Bool?
                            private enum CodingKeys: String, CodingKey {
                                case componentID = "component_id"
                                case name, hidden
                            }
                        }

                        let group: Group?
                        let component: Component?
                    }

                    let items: [Item]?
                }

                let affectedComponents: [AffectedComponent]?
                let structure: Structure?
                private enum CodingKeys: String, CodingKey {
                    case affectedComponents = "affected_components"
                    case structure
                }
            }

            let summary: Summary?
        }
        // swiftlint:enable nesting

        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let summary = response.summary,
              let items = summary.structure?.items,
              !items.isEmpty
        else {
            throw URLError(.cannotParseResponse)
        }

        var statusByID: [String: String] = [:]
        for affected in summary.affectedComponents ?? [] {
            statusByID[affected.componentID] = affected.status
        }

        func leaf(id: String, name: String) -> ProviderStatusComponent {
            let raw = statusByID[id] ?? "operational"
            return ProviderStatusComponent(
                id: id,
                name: name,
                indicator: ProviderStatusComponent.indicator(forStatuspageStatus: raw),
                status: raw)
        }

        var topLevel: [ProviderStatusComponent] = []
        for item in items {
            if let group = item.group, group.hidden != true {
                let children = (group.components ?? [])
                    .filter { $0.hidden != true }
                    .compactMap { child -> ProviderStatusComponent? in
                        guard let name = Self.normalizedStatusComponentName(child.name) else { return nil }
                        return leaf(id: child.componentID, name: name)
                    }
                guard let groupName = Self.normalizedStatusComponentName(group.name) else { continue }
                let worst = children.max { Self.indicatorRank($0.indicator) < Self.indicatorRank($1.indicator) }
                topLevel.append(ProviderStatusComponent(
                    id: group.id,
                    name: groupName,
                    indicator: worst?.indicator ?? .none,
                    status: worst?.status ?? "operational",
                    children: children))
            } else if let component = item.component,
                      component.hidden != true,
                      let name = Self.normalizedStatusComponentName(component.name)
            {
                topLevel.append(leaf(id: component.componentID, name: name))
            }
        }

        let leaves = topLevel.flatMap { $0.isGroup ? $0.children : [$0] }
        let overall = leaves.max { Self.indicatorRank($0.indicator) < Self.indicatorRank($1.indicator) }
        let status = ProviderStatus(
            indicator: overall?.indicator ?? .none,
            description: nil,
            updatedAt: nil)
        return (status, topLevel)
    }

    package static func parseStatuspageStatus(data: Data) throws -> ProviderStatus {
        struct Response: Decodable {
            struct Status: Decodable {
                let indicator: String
                let description: String?
            }

            struct Page: Decodable {
                let updatedAt: Date?

                private enum CodingKeys: String, CodingKey {
                    case updatedAt = "updated_at"
                }
            }

            let page: Page?
            let status: Status
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = StatusFeedDateParser.decodingStrategy()
        let response = try decoder.decode(Response.self, from: data)
        let indicator = ProviderStatusIndicator(rawValue: response.status.indicator) ?? .unknown
        return ProviderStatus(
            indicator: indicator,
            description: response.status.description,
            updatedAt: response.page?.updatedAt)
    }

    package static func parseStatuspageComponents(data: Data) throws -> [ProviderStatusComponent] {
        struct Response: Decodable {
            struct Component: Decodable {
                let id: String
                let name: String
                let status: String
                let group: Bool?
                let groupID: String?
                let position: Int?

                private enum CodingKeys: String, CodingKey {
                    case id, name, status, group, position
                    case groupID = "group_id"
                }
            }

            let components: [Component]?
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        let raw = (response.components ?? [])
            .filter { Self.normalizedStatusComponentName($0.name) != nil }
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }

        func makeRow(
            _ component: Response.Component,
            children: [ProviderStatusComponent]) -> ProviderStatusComponent
        {
            ProviderStatusComponent(
                id: component.id,
                name: Self.normalizedStatusComponentName(component.name) ?? component.name,
                indicator: ProviderStatusComponent.indicator(forStatuspageStatus: component.status),
                status: component.status,
                children: children)
        }

        // Children keyed by their parent group id, preserving position order.
        var childrenByGroup: [String: [ProviderStatusComponent]] = [:]
        for component in raw where component.group != true {
            guard let groupID = component.groupID else { continue }
            childrenByGroup[groupID, default: []].append(makeRow(component, children: []))
        }

        // Top-level rows: groups (with their children) and ungrouped leaf components, in order.
        return raw.compactMap { component in
            if component.group == true {
                return makeRow(component, children: childrenByGroup[component.id] ?? [])
            }
            // Skip leaves that belong to a group; they are rendered inside the group's dropdown.
            if component.groupID != nil { return nil }
            return makeRow(component, children: [])
        }
    }

    private nonisolated static func normalizedStatusComponentName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    private nonisolated static func indicatorRank(_ indicator: ProviderStatusIndicator) -> Int {
        switch indicator {
        case .none: 0
        case .maintenance: 1
        case .minor: 2
        case .major: 3
        case .critical: 4
        case .unknown: 1
        }
    }
}
