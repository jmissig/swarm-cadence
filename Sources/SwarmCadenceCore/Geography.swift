import Foundation

public struct GeographyAreaLocality: Codable, Equatable {
    public let locality: String
    public let region: String?
    public let postalCode: String?
    public let countryCode: String?

    public init(locality: String, region: String? = nil, postalCode: String? = nil, countryCode: String? = nil) {
        self.locality = locality
        self.region = region
        self.postalCode = postalCode
        self.countryCode = countryCode
    }
}

public struct NamedGeographyRequest: Codable, Equatable {
    public let nearPlace: String?
    public let area: String?

    public init(nearPlace: String?, area: String?) {
        self.nearPlace = nearPlace
        self.area = area
    }
}

public struct ResolvedGeography: Codable, Equatable {
    public let name: String
    public let scope: String
    public let kind: String
    public let displayName: String?
    public let latitude: Double?
    public let longitude: Double?
    public let radiusMeters: Double?
    public let localities: [GeographyAreaLocality]?

    public init(
        name: String,
        scope: String,
        kind: String,
        displayName: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusMeters: Double? = nil,
        localities: [GeographyAreaLocality]? = nil
    ) {
        self.name = name
        self.scope = scope
        self.kind = kind
        self.displayName = displayName
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.localities = localities
    }
}

public struct QueryGeography: Codable, Equatable {
    public let requested: NamedGeographyRequest
    public let resolved: ResolvedGeography?
    public let semantics: String

    public init(requested: NamedGeographyRequest, resolved: ResolvedGeography?, semantics: String) {
        self.requested = requested
        self.resolved = resolved
        self.semantics = semantics
    }
}

struct GeographyExpansion {
    let locality: String?
    let region: String?
    let postalCode: String?
    let countryCode: String?
    let nearLatitude: Double?
    let nearLongitude: Double?
    let radiusMeters: Double?
    let areaLocalities: [GeographyAreaLocality]
    let geography: QueryGeography
}

enum GeographyPresetResolver {
    static func resolve(
        account: String,
        configPath explicitConfigPath: String?,
        environment: [String: String],
        nearPlace: String?,
        area: String?,
        locality: String?,
        region: String?,
        postalCode: String?,
        countryCode: String?,
        nearLatitude: Double?,
        nearLongitude: Double?,
        radiusMeters: Double?
    ) throws -> GeographyExpansion {
        let nearPlace = try cleanOptionalName(nearPlace, optionName: "--near-place")
        let area = try cleanOptionalName(area, optionName: "--area")
        let requested = NamedGeographyRequest(nearPlace: nearPlace, area: area)

        if nearPlace != nil {
            if nearLatitude != nil || nearLongitude != nil {
                throw CLIError("--near-place cannot be combined with --near-lat or --near-lng.")
            }
        }
        if area != nil {
            if nearPlace != nil {
                throw CLIError("--area cannot be combined with --near-place.")
            }
            if locality != nil || region != nil || postalCode != nil || countryCode != nil {
                throw CLIError("--area cannot be combined with --locality, --region, --postal-code, or --country-code.")
            }
        }

        if nearPlace == nil && area == nil {
            try SwarmDatabase.validateGeoOptions(
                nearLatitude: nearLatitude,
                nearLongitude: nearLongitude,
                radiusMeters: radiusMeters
            )
            return GeographyExpansion(
                locality: locality,
                region: region,
                postalCode: postalCode,
                countryCode: countryCode,
                nearLatitude: nearLatitude,
                nearLongitude: nearLongitude,
                radiusMeters: radiusMeters,
                areaLocalities: [],
                geography: QueryGeography(
                    requested: requested,
                    resolved: nil,
                    semantics: geographySemantics(
                        hasPlaceFields: locality != nil || region != nil || postalCode != nil || countryCode != nil,
                        hasRadius: radiusMeters != nil,
                        hasArea: false,
                        hasNamedAnchor: false
                    )
                )
            )
        }

        let configPath = explicitConfigPath ?? AppSupportDefaults.configPath(environment: environment)
        guard let object = try SetupConfigStore.loadObjectIfPresent(path: configPath) else {
            throw CLIError("geography preset config not found: \(configPath)")
        }

        if let nearPlace {
            let preset = try findPreset(named: nearPlace, account: account, in: object)
            guard preset.kind == "anchor" else {
                throw CLIError("--near-place \(nearPlace) must reference an anchor geography preset.")
            }
            guard let latitude = preset.latitude else {
                throw CLIError("geography preset \(nearPlace) is missing latitude.")
            }
            guard let longitude = preset.longitude else {
                throw CLIError("geography preset \(nearPlace) is missing longitude.")
            }
            guard let effectiveRadius = radiusMeters ?? preset.defaultRadiusMeters else {
                throw CLIError("--near-place \(nearPlace) requires --radius-meters because the preset has no default_radius_meters.")
            }
            try SwarmDatabase.validateGeoOptions(
                nearLatitude: latitude,
                nearLongitude: longitude,
                radiusMeters: effectiveRadius
            )
            let resolved = ResolvedGeography(
                name: nearPlace,
                scope: preset.scope,
                kind: "anchor",
                displayName: preset.displayName,
                latitude: latitude,
                longitude: longitude,
                radiusMeters: effectiveRadius
            )
            return GeographyExpansion(
                locality: locality,
                region: region,
                postalCode: postalCode,
                countryCode: countryCode,
                nearLatitude: latitude,
                nearLongitude: longitude,
                radiusMeters: effectiveRadius,
                areaLocalities: [],
                geography: QueryGeography(
                    requested: requested,
                    resolved: resolved,
                    semantics: geographySemantics(hasPlaceFields: false, hasRadius: true, hasArea: false, hasNamedAnchor: true)
                )
            )
        }

        let areaName = area!
        let preset = try findPreset(named: areaName, account: account, in: object)
        guard preset.kind == "area" else {
            throw CLIError("--area \(areaName) must reference an area geography preset.")
        }
        guard !preset.localities.isEmpty else {
            throw CLIError("geography area preset \(areaName) must include at least one locality selector.")
        }
        let resolved = ResolvedGeography(
            name: areaName,
            scope: preset.scope,
            kind: "area",
            displayName: preset.displayName,
            localities: preset.localities
        )
        return GeographyExpansion(
            locality: nil,
            region: nil,
            postalCode: nil,
            countryCode: nil,
            nearLatitude: nearLatitude,
            nearLongitude: nearLongitude,
            radiusMeters: radiusMeters,
            areaLocalities: preset.localities,
            geography: QueryGeography(
                requested: requested,
                resolved: resolved,
                semantics: geographySemantics(
                    hasPlaceFields: false,
                    hasRadius: radiusMeters != nil,
                    hasArea: true,
                    hasNamedAnchor: false
                )
            )
        )
    }

    static func geographySemantics(
        hasPlaceFields: Bool,
        hasRadius: Bool,
        hasArea: Bool,
        hasNamedAnchor: Bool
    ) -> String {
        if hasArea && hasRadius {
            return "named factual venue-location area expansion AND explicit map-distance refinement"
        }
        if hasArea {
            return "named factual venue-location area expansion; this means in any listed place selector"
        }
        if hasNamedAnchor {
            return "named anchor/radius; this means near the resolved anchor and can include nearby localities"
        }
        switch (hasPlaceFields, hasRadius) {
        case (true, true):
            return "factual venue-location filters AND explicit map-distance refinement"
        case (true, false):
            return "factual venue-location filters; this means in the specified place fields"
        case (false, true):
            return "explicit map-distance filter around a caller-supplied anchor; this can include nearby localities"
        case (false, false):
            return "no geography filter"
        }
    }

    private struct Preset {
        let scope: String
        let kind: String
        let displayName: String?
        let latitude: Double?
        let longitude: Double?
        let defaultRadiusMeters: Double?
        let localities: [GeographyAreaLocality]
    }

    private static func cleanOptionalName(_ value: String?, optionName: String) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CLIError("\(optionName) must not be empty.")
        }
        return trimmed
    }

    private static func findPreset(named name: String, account: String, in object: [String: Any]) throws -> Preset {
        if let accounts = object["accounts"] as? [String: Any],
           let accountObject = accounts[account] as? [String: Any],
           let accountGeographies = accountObject["geographies"] as? [String: Any],
           let presetObject = accountGeographies[name] as? [String: Any] {
            return try parsePreset(presetObject, name: name, scope: "account")
        }
        if let geographies = object["geographies"] as? [String: Any],
           let presetObject = geographies[name] as? [String: Any] {
            return try parsePreset(presetObject, name: name, scope: "shared")
        }
        throw CLIError("unknown geography preset \(name) for account \(account).")
    }

    private static func parsePreset(_ object: [String: Any], name: String, scope: String) throws -> Preset {
        guard let rawKind = object["kind"] as? String else {
            throw CLIError("geography preset \(name) is missing kind.")
        }
        let kind = rawKind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == "anchor" || kind == "area" else {
            throw CLIError("geography preset \(name) kind must be anchor or area.")
        }
        let displayName = cleanString(object["display_name"] as? String)
        let latitude = object["latitude"] as? Double ?? (object["latitude"] as? Int).map(Double.init)
        let longitude = object["longitude"] as? Double ?? (object["longitude"] as? Int).map(Double.init)
        let defaultRadius = object["default_radius_meters"] as? Double ?? (object["default_radius_meters"] as? Int).map(Double.init)

        if kind == "anchor" {
            if let latitude, !(-90...90).contains(latitude) {
                throw CLIError("geography preset \(name) latitude must be between -90 and 90.")
            }
            if let longitude, !(-180...180).contains(longitude) {
                throw CLIError("geography preset \(name) longitude must be between -180 and 180.")
            }
            if let defaultRadius, defaultRadius <= 0 {
                throw CLIError("geography preset \(name) default_radius_meters must be greater than 0.")
            }
        }

        let localities = try parseLocalities(object["localities"], presetName: name)
        return Preset(
            scope: scope,
            kind: kind,
            displayName: displayName,
            latitude: latitude,
            longitude: longitude,
            defaultRadiusMeters: defaultRadius,
            localities: localities
        )
    }

    private static func parseLocalities(_ object: Any?, presetName: String) throws -> [GeographyAreaLocality] {
        guard let rawLocalities = object as? [[String: Any]] else { return [] }
        return try rawLocalities.map { raw in
            guard let locality = cleanString(raw["locality"] as? String) else {
                throw CLIError("geography area preset \(presetName) locality selectors require locality.")
            }
            return GeographyAreaLocality(
                locality: locality,
                region: cleanString(raw["region"] as? String),
                postalCode: cleanString(raw["postal_code"] as? String),
                countryCode: cleanString(raw["country_code"] as? String)
            )
        }
    }

    private static func cleanString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
