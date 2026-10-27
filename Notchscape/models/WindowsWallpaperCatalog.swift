// Catalog adapted from the user's MacScapes app. Artwork is downloaded on demand.
import Foundation

enum WindowsWallpaperCatalog {
    // Pinned to a known archive revision so future repository changes cannot break existing entries.
    private static let archiveRevision = "21970f48b8f66b4d44742cb30388c1454512d681"
    private static let rawRoot = "https://raw.githubusercontent.com/bartekl1/windows-ui-assets/\(archiveRevision)/Wallpapers/"

    private static func item(
        release: String,
        category: String,
        name: String,
        path: String,
        modern: Bool
    ) -> Wallpaper {
        let encodedPath = path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! }
            .joined(separator: "/")
        let fullURL = URL(string: rawRoot + encodedPath)!
        var thumbnail = URLComponents(string: "https://wsrv.nl/")!
        thumbnail.queryItems = [
            URLQueryItem(name: "url", value: fullURL.absoluteString),
            URLQueryItem(name: "w", value: "476"),
            URLQueryItem(name: "h", value: "232"),
            URLQueryItem(name: "fit", value: "cover"),
            URLQueryItem(name: "output", value: "jpg"),
            URLQueryItem(name: "q", value: "78")
        ]
        let identifier = "windows-" + path.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return Wallpaper(
            id: identifier,
            platform: .windows,
            isModern: modern,
            release: release,
            version: category,
            name: name,
            thumbnailURL: thumbnail.url!,
            downloadURL: fullURL
        )
    }

    private static func numbered(
        release: String,
        category: String,
        folder: String,
        numbers: [Int],
        modern: Bool,
        namePrefix: String? = nil,
        filePrefix: String = "img",
        fileExtension: String = "jpg"
    ) -> [Wallpaper] {
        numbers.map { number in
            item(
                release: release,
                category: category,
                name: "\(namePrefix ?? category) \(number)",
                path: "\(release)/\(folder)/\(filePrefix)\(number).\(fileExtension)",
                modern: modern
            )
        }
    }

    private static func lockScreens(release: String, modern: Bool, pngNumbers: Set<Int> = []) -> [Wallpaper] {
        (100...105).map { number in
            let fileExtension = pngNumbers.contains(number) ? "png" : "jpg"
            return item(
                release: release,
                category: "Lock Screen",
                name: "Lock Screen \(number - 99)",
                path: "\(release)/Lock screen/img\(number).\(fileExtension)",
                modern: modern
            )
        }
    }

    private static let windowsXP: [Wallpaper] = {
        let names = [
            "Bliss.bmp", "Windows XP.jpg", "Ascent.jpg", "Autumn.jpg", "Azul.jpg",
            "Crystal.jpg", "Follow.jpg", "Friend.jpg", "Home.jpg", "Moon flower.jpg",
            "Peace.jpg", "Power.jpg", "Purple flower.jpg", "Radiance.jpg",
            "Red moon desert.jpg", "Ripple.jpg", "Stonehenge.jpg", "Tulips.jpg",
            "Vortec space.jpg", "Wind.jpg"
        ]
        return names.map { file in
            item(
                release: "Windows XP",
                category: "Desktop",
                name: URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent,
                path: "Windows XP/Desktop/\(file)",
                modern: false
            )
        }
    }()

    private static let windowsVista = numbered(
        release: "Windows Vista",
        category: "Desktop",
        folder: "Desktop",
        numbers: Array(1...36),
        modern: false,
        namePrefix: "Vista Collection"
    )

    private static let windows7: [Wallpaper] = {
        var entries: [Wallpaper] = []
        entries.append(item(
            release: "Windows 7", category: "Desktop", name: "Windows 7",
            path: "Windows 7/Desktop/Windows/img0.jpg", modern: false
        ))
        let groups: [(String, ClosedRange<Int>)] = [
            ("Nature", 1...6), ("Landscapes", 7...12), ("Architecture", 13...18),
            ("Characters", 19...24), ("Scenes", 25...30)
        ]
        for (category, numbers) in groups {
            entries += numbered(
                release: "Windows 7", category: category,
                folder: "Desktop/\(category)", numbers: Array(numbers), modern: false
            )
        }
        let regions: [(String, String)] = [
            ("Australia", "AU"), ("Brazil", "BR"), ("Canada", "CA"), ("France", "FR"),
            ("Germany", "DE"), ("India", "IN"), ("Italy", "IT"), ("Japan", "JP"),
            ("Korea", "KR"), ("Mexico", "MX"), ("Netherlands", "NL"), ("Poland", "PL"),
            ("Russia", "RU"), ("South Africa", "ZA"), ("Spain", "ES"), ("Turkey", "TR"),
            ("United Kingdom", "GB"), ("United States", "US")
        ]
        for (region, code) in regions {
            for number in 1...6 {
                entries.append(item(
                    release: "Windows 7",
                    category: "Regional · \(region)",
                    name: "\(region) \(number)",
                    path: "Windows 7/Desktop Regional/\(region)/\(code)-wp\(number).jpg",
                    modern: false
                ))
            }
        }
        return entries
    }()

    private static let windows81: [Wallpaper] = {
        var entries = [item(
            release: "Windows 8.1", category: "Desktop", name: "Windows 8.1",
            path: "Windows 8.1/Desktop/Windows/img0.jpg", modern: true
        )]
        entries += numbered(release: "Windows 8.1", category: "Lines and Colors", folder: "Desktop/Lines and colors", numbers: [1, 2, 3, 4, 5, 6, 13], modern: true)
        entries += numbered(release: "Windows 8.1", category: "Flowers", folder: "Desktop/Flowers", numbers: Array(7...12), modern: true)
        entries += lockScreens(release: "Windows 8.1", modern: true, pngNumbers: [101, 103])
        return entries
    }()

    private static let windows10: [Wallpaper] = {
        var entries = [item(
            release: "Windows 10", category: "Desktop", name: "Windows 10 Hero",
            path: "Windows 10/Desktop/Windows/img0.jpg", modern: true
        )]
        entries += numbered(release: "Windows 10", category: "Windows 10", folder: "Desktop/Windows 10", numbers: [1, 2, 3, 4, 13], modern: true)
        entries += numbered(release: "Windows 10", category: "Flowers", folder: "Desktop/Flowers", numbers: Array(7...12), modern: true)
        entries += lockScreens(release: "Windows 10", modern: true, pngNumbers: [101, 103])
        return entries
    }()

    private static let windows11: [Wallpaper] = {
        var entries = [
            item(release: "Windows 11", category: "Windows", name: "Bloom Light", path: "Windows 11/Desktop/Windows/img0.jpg", modern: true),
            item(release: "Windows 11", category: "Windows", name: "Bloom Dark", path: "Windows 11/Desktop/Windows/img19.jpg", modern: true)
        ]
        let groups: [(String, ClosedRange<Int>)] = [
            ("Glow", 20...23), ("Captured Motion", 24...27),
            ("Sunrise", 28...31), ("Flow", 32...35)
        ]
        for (category, numbers) in groups {
            entries += numbered(release: "Windows 11", category: category, folder: "Desktop/\(category)", numbers: Array(numbers), modern: true)
        }
        entries += lockScreens(release: "Windows 11", modern: true)
        for appearance in ["Light", "Dark"] {
            for number in 0...3 {
                let padded = String(format: "%03d", number)
                entries.append(item(
                    release: "Windows 11",
                    category: "Touch Keyboard",
                    name: "Touch Keyboard \(appearance) \(number + 1)",
                    path: "Windows 11/Keyboard/TouchKeyboardTheme\(appearance)\(padded).jpg",
                    modern: true
                ))
            }
        }
        return entries
    }()

    static let all: [Wallpaper] = windows11 + windows10 + windows81 + windows7 + windowsVista + windowsXP
}
