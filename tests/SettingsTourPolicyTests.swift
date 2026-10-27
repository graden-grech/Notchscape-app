import Foundation

@main
struct SettingsTourPolicyTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func main() {
        check(SettingsTourChapter.allCases.count == 6, "Related settings fit six short chapters")
        let publicTopics = SettingsTourChapter.allCases.flatMap { $0.topics() }
        let allTopics = SettingsTourChapter.allCases.flatMap { $0.topics(accountsEnabled: true) }
        check(publicTopics.count == 18 && allTopics.count == 19, "Hidden account page is excluded unless explicitly enabled")
        check(Set(publicTopics.map(\.sectionID)).count == 18, "Each visible settings page is explained once")
        check(!publicTopics.contains(where: { $0.sectionID == "Account" }), "Disabled accounts are not advertised")
        for chapter in SettingsTourChapter.allCases {
            check(!chapter.title.isEmpty && !chapter.subtitle.isEmpty && !chapter.symbol.isEmpty, "Chapter has accessible copy and an SF symbol")
            check((2...4).contains(chapter.topics().count), "Each chapter contains a small group of pages")
        }
        for topic in allTopics {
            check(!topic.summary.isEmpty && !topic.suggestion.isEmpty, "Each settings page has an explanation and starting suggestion")
            check(topic.summary.count < 160 && topic.suggestion.count < 160, "Descriptions stay concise")
        }
        var progress = SettingsTourProgress()
        progress.back()
        check(progress.index == 0 && progress.isFirst && !progress.isFinished, "Back cannot run before the first page")
        for index in SettingsTourChapter.allCases.indices {
            check(progress.index == index && progress.chapter == SettingsTourChapter.allCases[index], "Navigation presents chapters in order")
            if index > 0 {
                progress.back(); check(progress.index == index - 1, "Back returns to the previous chapter")
                progress.next(); check(progress.index == index, "Next restores the current chapter")
            }
            progress.next()
        }
        check(progress.isFinished && progress.isLast, "Done finishes after the sixth chapter")
        let finished = progress
        progress.next(); progress.back()
        check(progress == finished, "Finished navigation cannot leave valid bounds")
        for index in SettingsTourChapter.allCases.indices {
            var skipped = SettingsTourProgress()
            for _ in 0..<index { skipped.next() }
            skipped.skip()
            check(skipped.isFinished && skipped.index == index, "Skip is available on every page and carries no setting payload")
            let snapshot = skipped
            skipped.next(); skipped.back()
            check(skipped == snapshot, "A skipped tour cannot advance or reopen itself")
        }
        check(SettingsTourProgress().index == 0, "Replay starts a fresh in-memory tour")
        print("PASS: \(checks) guided settings navigation and catalog checks")
    }
}
