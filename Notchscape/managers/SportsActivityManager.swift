import Combine
import Defaults
import Foundation
import OSLog

struct SportsTeam: Equatable, Identifiable {
    let id: String
    let name: String
    let abbreviation: String
    let score: String
    let logoURL: URL?
    let colorHex: String?
}

struct SportsDirectoryTeam: Equatable, Identifiable {
    let id: String
    let league: SportsLeague
    let name: String
    let abbreviation: String
    let logoURL: URL?
    let colorHex: String?

    var favoriteKey: String { "\(league.rawValue):\(id)" }
}

struct SportsGame: Equatable, Identifiable {
    let id: String
    let league: SportsLeague
    let away: SportsTeam
    let home: SportsTeam
    let state: String
    let statusText: String
    let startDate: Date
    let gameURL: URL?

    var isLive: Bool { state == "in" }
    var isUpcoming: Bool { state == "pre" }
    var isFinal: Bool { state == "post" }

    var scoreSummary: String {
        "\(away.abbreviation) \(displayScore(for: away))  •  \(home.abbreviation) \(displayScore(for: home))"
    }

    func displayScore(for team: SportsTeam) -> String {
        isUpcoming && team.score == "0" ? "–" : team.score
    }
}

struct SportsScoreBanner: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let game: SportsGame
}

@MainActor
final class SportsActivityManager: ObservableObject {
    static let shared = SportsActivityManager()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "theboringteam.boringnotch",
        category: "SportsActivity"
    )

    @Published private(set) var currentGame: SportsGame?
    @Published private(set) var scoreBanner: SportsScoreBanner?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var availableTeams: [SportsDirectoryTeam] = []
    @Published private(set) var isLoadingTeams = false
    @Published private(set) var teamsErrorMessage: String?

    private var pollingTask: Task<Void, Never>?
    private var bannerDismissalTask: Task<Void, Never>?
    private var previousGame: SportsGame?

    private init() {}

    func start() {
        guard Defaults[.sportsActivitiesEnabled] else {
            Self.logger.debug("Sports polling skipped because the feature is disabled")
            return
        }
        guard pollingTask == nil else { return }

        Self.logger.info("Starting sports polling for \(self.configuredLeagues.count) league(s)")

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval: TimeInterval = self.currentGame?.isLive == true
                    ? (AppPerformanceManager.shared.lowImpact ? 30 : 15)
                    : (AppPerformanceManager.shared.lowImpact ? 120 : 60)
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        Self.logger.debug("Stopping sports polling")
        pollingTask?.cancel()
        pollingTask = nil
        bannerDismissalTask?.cancel()
        bannerDismissalTask = nil
        scoreBanner = nil
    }

    func configurationChanged() {
        stop()
        previousGame = nil
        currentGame = nil
        errorMessage = nil
        if Defaults[.sportsActivitiesEnabled] {
            start()
        }
    }

    func refresh() async {
        guard Defaults[.sportsActivitiesEnabled], !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var games: [SportsGame] = []
        var lastFailure: Error?
        var successfulFeeds = 0

        for league in configuredLeagues {
            do {
                let leagueGames = try await fetchGames(for: league)
                games.append(contentsOf: leagueGames)
                successfulFeeds += 1
            } catch is CancellationError {
                return
            } catch {
                lastFailure = error
                Self.logger.error("\(league.rawValue, privacy: .public) scoreboard failed: \(String(describing: error), privacy: .public)")
            }
        }

        if successfulFeeds > 0 {
            let selected = selectGame(from: games)
            updateCurrentGame(selected)
            lastUpdated = .now
            Self.logger.info(
                "Loaded \(games.count) games; selected \(selected?.id ?? "none", privacy: .public)"
            )
        } else {
            errorMessage = lastFailure?.localizedDescription ?? SportsFeedError.unavailable.localizedDescription
        }
    }

    func loadTeams(for league: SportsLeague) async {
        guard !isLoadingTeams,
              let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.endpointPath)/teams?limit=1000") else { return }

        isLoadingTeams = true
        teamsErrorMessage = nil
        defer { isLoadingTeams = false }

        do {
            let data = try await requestData(from: url)
            let directory = try JSONDecoder().decode(ESPNTeamDirectory.self, from: data)
            let teams = directory.sports
                .flatMap(\.leagues)
                .flatMap(\.teams)
                .compactMap { entry -> SportsDirectoryTeam? in
                    guard let id = entry.team.id,
                          let name = entry.team.displayName,
                          let abbreviation = entry.team.abbreviation else { return nil }
                    let logo = entry.team.logos?.first(where: {
                        $0.rel?.contains("default") == true && $0.rel?.contains("dark") != true
                    })?.href
                        ?? entry.team.logos?.first?.href
                    return SportsDirectoryTeam(
                        id: id,
                        league: league,
                        name: name,
                        abbreviation: abbreviation,
                        logoURL: logo.flatMap(URL.init(string:)),
                        colorHex: entry.team.color
                    )
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            availableTeams = teams
        } catch is CancellationError {
            return
        } catch {
            availableTeams = []
            teamsErrorMessage = "Teams are temporarily unavailable."
            Self.logger.error("Team directory failed: \(String(describing: error), privacy: .public)")
        }
    }

    func showScorePreview() {
        let game = currentGame ?? sampleGame(for: Defaults[.sportsLeague])
        presentBanner(title: game.isFinal ? "Final score" : "Score update", detail: game.scoreSummary, game: game)
    }

    private func selectGame(from games: [SportsGame]) -> SportsGame? {
        let favoriteKeys = Defaults[.sportsFavoriteTeams]
        let filter = Defaults[.sportsFavoriteTeam]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let matchingGames: [SportsGame]
        if !favoriteKeys.isEmpty {
            matchingGames = games.filter { game in
                favoriteKeys.contains("\(game.league.rawValue):\(game.away.id)")
                    || favoriteKeys.contains("\(game.league.rawValue):\(game.home.id)")
            }
        } else if filter.isEmpty {
            matchingGames = games
        } else {
            let terms = filter.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            matchingGames = games.filter { game in
                terms.contains { term in
                    [game.away.abbreviation, game.away.name, game.home.abbreviation, game.home.name]
                        .contains { $0.lowercased().contains(term) }
                }
            }
        }

        let candidates = matchingGames.filter { game in
            game.isLive || game.isFinal || (Defaults[.sportsShowUpcoming] && game.isUpcoming)
        }

        return candidates.sorted { lhs, rhs in
            let lhsRank = lhs.isLive ? 0 : lhs.isUpcoming ? 1 : 2
            let rhsRank = rhs.isLive ? 0 : rhs.isUpcoming ? 1 : 2
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.isFinal { return lhs.startDate > rhs.startDate }
            return lhs.startDate < rhs.startDate
        }.first
    }

    private var configuredLeagues: [SportsLeague] {
        let selected = Defaults[.sportsEnabledLeagues]
        if selected.isEmpty { return [Defaults[.sportsLeague]] }
        return SportsLeague.allCases.filter(selected.contains)
    }

    private func fetchGames(for league: SportsLeague) async throws -> [SportsGame] {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.endpointPath)/scoreboard") else {
            throw SportsFeedError.unavailable
        }
        Self.logger.debug("Fetching \(league.rawValue, privacy: .public) scoreboard")
        let data = try await requestData(from: url)
        let feed = try JSONDecoder().decode(ESPNScoreboard.self, from: data)
        return feed.events.compactMap { makeGame(from: $0, league: league) }
    }

    private func requestData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Notchscape Sports/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw SportsFeedError.unavailable
        }
        return data
    }

    private func updateCurrentGame(_ game: SportsGame?) {
        defer {
            previousGame = game
            currentGame = game
        }

        guard Defaults[.sportsScoreNotificationsEnabled],
              let old = previousGame,
              let game,
              old.id == game.id else { return }

        let awayChanged = old.away.score != game.away.score
        let homeChanged = old.home.score != game.home.score
        let statusChanged = old.state != game.state

        if awayChanged || homeChanged {
            let scoringTeam: SportsTeam?
            if scoreValue(game.away.score) > scoreValue(old.away.score) {
                scoringTeam = game.away
            } else if scoreValue(game.home.score) > scoreValue(old.home.score) {
                scoringTeam = game.home
            } else {
                scoringTeam = nil
            }
            presentBanner(
                title: scoringTeam.map { "\($0.abbreviation) scored" } ?? "Score update",
                detail: game.scoreSummary,
                game: game
            )
        } else if statusChanged {
            presentBanner(
                title: game.isFinal ? "Final score" : game.isLive ? "Game started" : "Game update",
                detail: game.scoreSummary,
                game: game
            )
        }
    }

    private func presentBanner(title: String, detail: String, game: SportsGame) {
        bannerDismissalTask?.cancel()
        scoreBanner = SportsScoreBanner(title: title, detail: detail, game: game)
        bannerDismissalTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.scoreBanner = nil
            self?.bannerDismissalTask = nil
        }
    }

    private func scoreValue(_ score: String) -> Double {
        Double(score) ?? 0
    }

    private func makeGame(from event: ESPNEvent, league: SportsLeague) -> SportsGame? {
        guard let id = event.id,
              let date = event.date,
              let status = event.status?.type,
              let competition = event.competitions?.first,
              let competitors = competition.competitors,
              let home = competitors.first(where: { $0.homeAway == "home" }),
              let away = competitors.first(where: { $0.homeAway == "away" }),
              let startDate = Self.fractionalDateFormatter.date(from: date)
                ?? Self.dateFormatter.date(from: date)
                ?? Self.shortDateFormatter.date(from: date) else {
            Self.logger.debug("Skipping an incomplete sports event")
            return nil
        }

        let gameLink = event.links?.first(where: { $0.rel?.contains("summary") == true })?.href
        return SportsGame(
            id: id,
            league: league,
            away: makeTeam(from: away),
            home: makeTeam(from: home),
            state: status.state ?? "pre",
            statusText: status.shortDetail ?? status.detail ?? status.description ?? "Scheduled",
            startDate: startDate,
            gameURL: gameLink.flatMap(URL.init(string:))
        )
    }

    private func makeTeam(from competitor: ESPNCompetitor) -> SportsTeam {
        let team = competitor.team
        let abbreviation = team?.abbreviation ?? "TEAM"
        return SportsTeam(
            id: team?.id ?? abbreviation,
            name: team?.displayName ?? abbreviation,
            abbreviation: abbreviation,
            score: competitor.score ?? "0",
            logoURL: team?.logo.flatMap(highResolutionLogoURL),
            colorHex: team?.color
        )
    }

    private func sampleGame(for league: SportsLeague) -> SportsGame {
        let teams: (away: String, home: String, awayScore: String, homeScore: String)
        switch league {
        case .nfl: teams = ("DET", "GB", "24", "17")
        case .mlb: teams = ("DET", "CLE", "5", "3")
        case .nhl: teams = ("DET", "TOR", "3", "2")
        case .mls: teams = ("MIA", "CLB", "2", "1")
        case .wnba: teams = ("IND", "NY", "78", "74")
        case .collegeFootball: teams = ("MICH", "OSU", "27", "24")
        case .collegeBasketball: teams = ("MICH", "MSU", "72", "68")
        case .nba: teams = ("DET", "CLE", "104", "101")
        }

        return SportsGame(
            id: "sports-preview",
            league: league,
            away: SportsTeam(id: "preview-away", name: teams.away, abbreviation: teams.away, score: teams.awayScore, logoURL: nil, colorHex: "5A7DFF"),
            home: SportsTeam(id: "preview-home", name: teams.home, abbreviation: teams.home, score: teams.homeScore, logoURL: nil, colorHex: "FF453A"),
            state: "in",
            statusText: "4th 2:18",
            startDate: .now,
            gameURL: nil
        )
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatter = ISO8601DateFormatter()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mmX"
        return formatter
    }()

    private func highResolutionLogoURL(_ source: String) -> URL? {
        URL(string: source.replacingOccurrences(of: "/scoreboard/", with: "/"))
    }
}

private enum SportsFeedError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Live scores are temporarily unavailable"
    }
}

private struct ESPNScoreboard: Decodable {
    let events: [ESPNEvent]
}

private struct ESPNEvent: Decodable {
    let id: String?
    let date: String?
    let status: ESPNStatus?
    let competitions: [ESPNCompetition]?
    let links: [ESPNLink]?
}

private struct ESPNStatus: Decodable {
    let type: ESPNStatusType?
}

private struct ESPNStatusType: Decodable {
    let state: String?
    let description: String?
    let detail: String?
    let shortDetail: String?
}

private struct ESPNCompetition: Decodable {
    let competitors: [ESPNCompetitor]?
}

private struct ESPNCompetitor: Decodable {
    let homeAway: String?
    let score: String?
    let team: ESPNTeam?
}

private struct ESPNTeam: Decodable {
    let id: String?
    let abbreviation: String?
    let displayName: String?
    let color: String?
    let logo: String?
}

private struct ESPNLink: Decodable {
    let rel: [String]?
    let href: String?
}

private struct ESPNTeamDirectory: Decodable {
    let sports: [ESPNDirectorySport]
}

private struct ESPNDirectorySport: Decodable {
    let leagues: [ESPNDirectoryLeague]
}

private struct ESPNDirectoryLeague: Decodable {
    let teams: [ESPNDirectoryEntry]
}

private struct ESPNDirectoryEntry: Decodable {
    let team: ESPNDirectoryTeam
}

private struct ESPNDirectoryTeam: Decodable {
    let id: String?
    let abbreviation: String?
    let displayName: String?
    let color: String?
    let logos: [ESPNDirectoryLogo]?
}

private struct ESPNDirectoryLogo: Decodable {
    let href: String?
    let rel: [String]?
}
