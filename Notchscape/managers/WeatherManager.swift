import Combine
import AppKit
@preconcurrency import CoreLocation
import Defaults
import Foundation

struct WeatherSnapshot: Equatable {
    let location: String
    let temperature: Double
    let apparentTemperature: Double
    let weatherCode: Int
    let high: Double
    let low: Double
    let updatedAt: Date
    var isDay = true

    var symbol: String {
        switch weatherCode {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    var condition: String {
        switch weatherCode {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Foggy"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorms"
        default: "Current conditions"
        }
    }

    var isAlertWorthy: Bool {
        switch weatherCode {
        case 65...67, 75...77, 82, 86, 95...99: true
        default: false
        }
    }
}

@MainActor
final class WeatherManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = WeatherManager()

    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus

    private let locationManager = CLLocationManager()
    private var refreshTask: Task<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var locationTimeoutTask: Task<Void, Never>?
    private var generation = 0
    private var configurationKey = ""
    private var successfulConfigurationKey = ""
    private var observations = Set<AnyCancellable>()
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        return URLSession(configuration: configuration)
    }()

    private override init() {
        locationAuthorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        Defaults.publisher(.weatherEnabled).dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(force: true) }.store(in: &observations)

        if Defaults[.weatherEnabled],
           Defaults[.weatherUseCurrentLocation] || !Defaults[.weatherLocation].isEmpty {
            refresh()
        }
    }

    func refresh(force: Bool = false, requestPermission: Bool = false) {
        let location = Defaults[.weatherLocation].trimmingCharacters(in: .whitespacesAndNewlines)
        let useCurrentLocation = Defaults[.weatherUseCurrentLocation]
        guard Defaults[.weatherEnabled], useCurrentLocation || !location.isEmpty else {
            generation += 1; refreshTask?.cancel(); cancelLocationRequest(); isLoading = false
            weather = nil
            errorMessage = useCurrentLocation ? nil : "Enter a city or postal code"
            return
        }

        let key = "\(useCurrentLocation)|\(location)|\(Defaults[.weatherUseCelsius])"
        if configurationKey == key, isLoading { return }
        if !force, successfulConfigurationKey == key, let weather, Date().timeIntervalSince(weather.updatedAt) < 900 { return }
        if useCurrentLocation, locationManager.authorizationStatus == .notDetermined, !requestPermission {
            errorMessage = "Choose Use My Location to allow local weather, or enter a city in Weather settings."
            return
        }

        generation += 1
        let run = generation
        configurationKey = key
        refreshTask?.cancel()
        cancelLocationRequest()
        isLoading = true
        refreshTask = Task {
            errorMessage = nil
            defer { if run == generation { isLoading = false } }

            do {
                try Task.checkCancellation()
                let snapshot: WeatherSnapshot
                if useCurrentLocation {
                    let currentLocation = try await requestCurrentLocation()
                    snapshot = try await fetchWeather(
                        latitude: (currentLocation.coordinate.latitude * 100).rounded() / 100,
                        longitude: (currentLocation.coordinate.longitude * 100).rounded() / 100,
                        locationName: "Current location"
                    )
                } else {
                    let place = try await geocode(location)
                    snapshot = try await fetchWeather(
                        latitude: place.latitude,
                        longitude: place.longitude,
                        locationName: [place.name, place.admin1].compactMap { $0 }.joined(separator: ", ")
                    )
                }
                try Task.checkCancellation()
                guard run == generation else { return }
                weather = snapshot
                successfulConfigurationKey = key
            } catch is CancellationError {
                return
            } catch {
                if run == generation { errorMessage = error.localizedDescription }
            }
        }
    }

    func useMyLocation() {
        // An explicit action brings the app forward; background tile appearance
        // must never trigger an invisible, repeated permission request.
        NSApp.activate(ignoringOtherApps: true)
        refresh(force: true, requestPermission: true)
    }

    var locationPermissionDescription: String {
        switch locationAuthorizationStatus {
        case .notDetermined: "Location access has not been requested yet"
        case .restricted: "Location access is restricted"
        case .denied: "Location access is off for Notchscape"
        case .authorizedAlways, .authorizedWhenInUse: "Location access is on"
        @unknown default: "Location access status is unavailable"
        }
    }

    private func requestCurrentLocation() async throws -> CLLocation {
        guard await Task.detached(priority: .utility, operation: { CLLocationManager.locationServicesEnabled() }).value else {
            throw WeatherError.locationServicesDisabled
        }
        try Task.checkCancellation()

        if locationContinuation != nil {
            cancelLocationRequest()
        }

        if locationManager.authorizationStatus == .authorizedAlways,
           let cached = locationManager.location, cached.horizontalAccuracy >= 0,
           Date().timeIntervalSince(cached.timestamp) >= 0, Date().timeIntervalSince(cached.timestamp) < 600 {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation

            switch locationManager.authorizationStatus {
            case .notDetermined:
                // macOS requests consent when a location service starts. The
                // iOS-style authorization call alone can leave a menu-bar app
                // waiting forever without presenting a prompt.
                locationManager.requestLocation()
            case .authorizedAlways, .authorizedWhenInUse:
                locationManager.requestLocation()
            case .denied:
                finishLocationRequest(.failure(WeatherError.locationPermissionDenied))
            case .restricted:
                finishLocationRequest(.failure(WeatherError.locationPermissionRestricted))
            @unknown default:
                finishLocationRequest(.failure(WeatherError.locationPermissionDenied))
            }

            let waitingForConsent = locationManager.authorizationStatus == .notDetermined
            locationTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(waitingForConsent ? 90 : 15))
                guard !Task.isCancelled else { return }
                self?.finishLocationRequest(.failure(WeatherError.locationTimedOut))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAuthorizationStatus = manager.authorizationStatus
        guard locationContinuation != nil else {
            if manager.authorizationStatus == .authorizedAlways, Defaults[.weatherEnabled], Defaults[.weatherUseCurrentLocation] { refresh() }
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied:
            finishLocationRequest(.failure(WeatherError.locationPermissionDenied))
        case .restricted:
            finishLocationRequest(.failure(WeatherError.locationPermissionRestricted))
        case .notDetermined:
            break
        @unknown default:
            finishLocationRequest(.failure(WeatherError.locationPermissionDenied))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finishLocationRequest(.failure(WeatherError.locationUnavailable))
            return
        }
        finishLocationRequest(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationAuthorizationStatus = manager.authorizationStatus
        if let error = error as? CLError, error.code == .denied {
            finishLocationRequest(.failure(WeatherError.locationPermissionDenied))
        } else { finishLocationRequest(.failure(error)) }
    }

    private func finishLocationRequest(_ result: Result<CLLocation, Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        continuation.resume(with: result)
    }

    private func cancelLocationRequest() {
        guard locationContinuation != nil else { return }
        finishLocationRequest(.failure(CancellationError()))
    }

    private func geocode(_ query: String) async throws -> GeoResult {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response)
        guard data.count < 1_000_000 else { throw WeatherError.invalidResponse }
        let payload = try JSONDecoder().decode(GeoResponse.self, from: data)
        guard let result = payload.results?.first else { throw WeatherError.locationNotFound }
        return result
    }

    private func fetchWeather(latitude: Double, longitude: Double, locationName: String) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: Defaults[.weatherUseCelsius] ? "celsius" : "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response)
        guard data.count < 1_000_000 else { throw WeatherError.invalidResponse }
        let payload = try JSONDecoder().decode(ForecastResponse.self, from: data)
        guard let high = payload.daily.temperature2mMax.first, let low = payload.daily.temperature2mMin.first else {
            throw WeatherError.invalidResponse
        }
        return WeatherSnapshot(
            location: locationName,
            temperature: payload.current.temperature2m,
            apparentTemperature: payload.current.apparentTemperature,
            weatherCode: payload.current.weatherCode,
            high: high,
            low: low,
            updatedAt: .now,
            isDay: payload.current.isDay != 0
        )
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw WeatherError.invalidResponse
        }
    }
}

private enum WeatherError: LocalizedError {
    case locationNotFound
    case locationServicesDisabled
    case locationPermissionDenied
    case locationPermissionRestricted
    case locationTimedOut
    case locationUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .locationNotFound: "Location not found"
        case .locationServicesDisabled: "Location Services are turned off"
        case .locationPermissionDenied: "Allow location access in System Settings to use local weather"
        case .locationPermissionRestricted: "Location access is restricted on this Mac"
        case .locationTimedOut: "The location request timed out"
        case .locationUnavailable: "Your current location is unavailable"
        case .invalidResponse: "Weather service did not return valid data"
        }
    }
}

private struct GeoResponse: Decodable { let results: [GeoResult]? }
private struct GeoResult: Decodable {
    let name: String
    let admin1: String?
    let latitude: Double
    let longitude: Double
}

private struct ForecastResponse: Decodable {
    let current: Current
    let daily: Daily

    struct Current: Decodable {
        let temperature2m: Double
        let apparentTemperature: Double
        let weatherCode: Int
        let isDay: Int?

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    struct Daily: Decodable {
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]

        enum CodingKeys: String, CodingKey {
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
        }
    }
}
