// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveWallpaper",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LiveWallpaperCore", targets: ["LiveWallpaperCore"]),
        .executable(name: "LiveWallpaper", targets: ["LiveWallpaper"]),
        // ターゲット名にハイフンは使えないため NativeHost とし、
        // app bundle への配置時に install.sh / release.sh 側で native-host へ改名する
        .executable(name: "NativeHost", targets: ["NativeHost"]),
    ],
    targets: [
        // 純粋ロジック(URL/ID 解析・watch URL 構築・設定ファイル入出力・診断ログ)。AppKit 非依存
        .target(name: "LiveWallpaperCore"),
        // 壁紙アプリ本体(AppKit)
        .executableTarget(
            name: "LiveWallpaper",
            dependencies: ["LiveWallpaperCore"],
            exclude: ["Info.plist", "icon.icns"]
        ),
        // Chrome Native Messaging host
        .executableTarget(
            name: "NativeHost",
            dependencies: ["LiveWallpaperCore"]
        ),
        .testTarget(
            name: "LiveWallpaperCoreTests",
            dependencies: ["LiveWallpaperCore"]
        ),
    ]
)
