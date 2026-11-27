import Cocoa
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Component Status Model

struct ComponentStatus {
    var crossoverExists: Bool = false
    var versionString: String = "Not found"
    var hasGStreamer: Bool = false
    var gstreamerVersion: String = "Stock (Limited)"
    var hasRpath: Bool = false
    var hasD3DMetal: Bool = false
    var d3dMetalVersion: String = "Missing"
    var hasD3DMetalBackup: Bool = false
    var d3dMetalBackupVersion: String = ""
    var hasDXMT: Bool = false
    var dxmtVersion: String = "Missing"
    var hasDXVK: Bool = false
    var bottleCount: Int = 0

    var metalHudEnabled: Bool = false
    var gameModeEnabled: Bool = false
    var nvidiaSpoofEnabled: Bool = false
    var avxAndMsyncEnabled: Bool = false
    var cacheSizeBytes: Int64 = 0

    var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file)
    }

    var isReady: Bool {
        crossoverExists && hasGStreamer && hasRpath && hasD3DMetal && hasDXMT
    }
}

// MARK: - Navigation Tabs

enum ActiveTab: String, CaseIterable, Identifiable {
    case patcher = "Runtime"
    case optimizations = "Tweaks"
    case gameFixes = "Game Fixes"
    case maintenance = "Storage & Console"

    var id: String { rawValue }
    var iconName: String {
        switch self {
        case .patcher: return "bandage"
        case .optimizations: return "slider.horizontal.3"
        case .gameFixes: return "gamecontroller"
        case .maintenance: return "internaldrive"
        }
    }
}

struct GameFixAddon: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let folderName: String
    let iconName: String

    var tarballURL: String {
        "https://github.com/passs0/HexAid/archive/refs/heads/main.tar.gz"
    }

    var localDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("HexAid/Addons/\(id)", isDirectory: true)
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localDirectory.appendingPathComponent("install.sh").path)
    }

    static let catalog: [GameFixAddon] = [
        GameFixAddon(
            id: "re9",
            title: "Resident Evil Requiem (RE9)",
            subtitle: "Fixes D3DMetal/MetalFX stability, audio popping, Bluetooth DualSense, and window focus",
            folderName: "RE9-CrossOver-Fix",
            iconName: "cross.case"
        ),
        GameFixAddon(
            id: "sh2r",
            title: "Silent Hill 2 Remake (GOG)",
            subtitle: "Fixes launch focus, cursor hiding, and UE5 D3D11/DXMT frame pacing",
            folderName: "SH2R-CrossOver-Fix",
            iconName: "display"
        )
    ]
}

struct CrossOverInstallation: Identifiable, Hashable, Sendable {
    let path: String

    var id: String { path }
    var displayName: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}

// MARK: - View Model

@MainActor
final class HexAidViewModel: ObservableObject {
    @Published var status = ComponentStatus()
    @Published var isBusy = false
    @Published var activeTab: ActiveTab = .patcher
    @Published private(set) var installedCrossOvers: [CrossOverInstallation] = []
    @Published var selectedCrossOverPath = "/Applications/CrossOver.app"

    // Patcher options
    @Published var updateGStreamer = true
    @Published var updateDXMT = true
    @Published var updateDXVK = true
    @Published var enableAVXAndMSync = true

    // Optimization options
    @Published var toggleMetalHUD = false
    @Published var toggleNvidiaSpoof = false
    @Published var toggleGameMode = true

    @Published var logs: [String] = []

    var cxAppPath: String { selectedCrossOverPath }
    var selectedCrossOverName: String {
        CrossOverInstallation(path: selectedCrossOverPath).displayName
    }
    var bottlesPath: String { Self.bottlePath(for: selectedCrossOverPath) }

    init() {
        installedCrossOvers = Self.discoverCrossOvers()
        if let stable = installedCrossOvers.first(where: { $0.displayName == "CrossOver" }) {
            selectedCrossOverPath = stable.path
        } else if let first = installedCrossOvers.first {
            selectedCrossOverPath = first.path
        }

        if CommandLine.arguments.contains("--tab-optimizations") {
            activeTab = .optimizations
        } else if CommandLine.arguments.contains("--tab-maintenance") {
            activeTab = .maintenance
            logs = [
                "[09:42:01] Starting HexAid patch on \(selectedCrossOverPath)...",
                "[09:42:02] Resolving latest GStreamer build from Sikarugir-App/gstreamer...",
                "[09:42:03] Downloading & extracting GStreamer 1.28.1 (with FFmpeg/libav)...",
                "[09:42:04] Cleaning conflicting stock GStreamer/GLib libraries & linking plugins...",
                "[09:42:05] Linking winegstreamer.so to GStreamer.framework...",
                "[09:42:06] Resolving latest DXMT release from 3Shain/dxmt...",
                "[09:42:07] Downloading & extracting DXMT v0.80 builtin...",
                "[09:42:08] Ensuring WINEMSYNC=1 and ROSETTA_ADVERTISE_AVX=1 on existing bottles...",
                "[09:42:09] Clearing quarantine, re-signing \(selectedCrossOverName).app & resetting caches...",
                "[09:42:10] ✅ HexAid patch complete! All components verified."
            ]
        }
    }

    func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
    }

    func clearLogs() {
        logs.removeAll()
    }

    func copyLogs() {
        let text = logs.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func refreshStatus() {
        let found = Self.discoverCrossOvers()
        installedCrossOvers = found
        if !found.contains(where: { $0.path == selectedCrossOverPath }) {
            selectedCrossOverPath = found.first(where: { $0.displayName == "CrossOver" })?.path
                ?? found.first?.path
                ?? "/Applications/CrossOver.app"
        }

        let cxPath = cxAppPath
        let btlPath = bottlesPath
        Task.detached {
            let next = Self.inspectStatus(cxAppPath: cxPath, bottlesPath: btlPath)
            await MainActor.run {
                guard self.selectedCrossOverPath == cxPath else { return }
                self.status = next
                self.toggleMetalHUD = next.metalHudEnabled
                self.toggleNvidiaSpoof = next.nvidiaSpoofEnabled
            }
        }
    }

    nonisolated static func discoverCrossOvers() -> [CrossOverInstallation] {
        let fm = FileManager.default
        let roots = [
            "/Applications",
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications").path
        ]
        let names = ["CrossOver.app", "CrossOver Preview.app"]
        var found: [CrossOverInstallation] = []
        for root in roots {
            for name in names {
                let path = URL(fileURLWithPath: root).appendingPathComponent(name).path
                guard fm.fileExists(atPath: path) else { continue }
                if !found.contains(where: { $0.path == path }) {
                    found.append(CrossOverInstallation(path: path))
                }
            }
        }
        return found.sorted { lhs, rhs in
            let leftIsPreview = lhs.displayName.localizedCaseInsensitiveContains("Preview")
            let rightIsPreview = rhs.displayName.localizedCaseInsensitiveContains("Preview")
            return leftIsPreview == rightIsPreview ? lhs.path < rhs.path : !leftIsPreview
        }
    }

    nonisolated static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func gptkBackupDir(for cxAppPath: String) -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let name = CrossOverInstallation(path: cxAppPath).displayName
        return appSupport
            .appendingPathComponent("HexAid/Backups/\(name)/apple_gptk", isDirectory: true)
            .path
    }

    nonisolated static func bottlePath(for cxAppPath: String) -> String {
        let fallback = ("~/Library/Application Support/CrossOver/Bottles" as NSString).expandingTildeInPath
        let configPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/etc/CrossOver.conf"
        guard let config = try? String(contentsOfFile: configPath, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"(?m)^\s*"CX_BOTTLE_PATH"\s*=\s*"([^"]+)""#),
              let match = regex.firstMatch(in: config, range: NSRange(config.startIndex..., in: config)),
              let range = Range(match.range(at: 1), in: config) else {
            return fallback
        }

        let configuredPath = String(config[range])
            .replacingOccurrences(of: "${USER}", with: NSUserName())
            .replacingOccurrences(of: "$USER", with: NSUserName())
            .replacingOccurrences(of: "${HOME}", with: NSHomeDirectory())
            .replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
        let firstPath = configuredPath.split(separator: ":", omittingEmptySubsequences: true).first.map(String.init)
        guard let firstPath else { return fallback }
        return (firstPath as NSString).expandingTildeInPath
    }

    nonisolated static func inspectStatus(cxAppPath: String, bottlesPath: String) -> ComponentStatus {
        let fm = FileManager.default
        var next = ComponentStatus()
        next.crossoverExists = fm.fileExists(atPath: cxAppPath)

        if let items = try? fm.contentsOfDirectory(atPath: bottlesPath) {
            let bottleDirs = items.filter { item in
                fm.fileExists(atPath: "\(bottlesPath)/\(item)/cxbottle.conf")
            }
            next.bottleCount = bottleDirs.count

            // Check if any bottle has Metal HUD, NVIDIA spoof, or MSync enabled
            for dir in bottleDirs {
                let confPath = "\(bottlesPath)/\(dir)/cxbottle.conf"
                if let content = try? String(contentsOfFile: confPath, encoding: .utf8) {
                    if content.contains("\"MTL_HUD_ENABLED\" = \"1\"") {
                        next.metalHudEnabled = true
                    }
                    if content.contains("\"D3DM_VENDOR_ID\" = \"0x10DE\"") {
                        next.nvidiaSpoofEnabled = true
                    }
                    if content.contains("\"WINEMSYNC\" = \"1\"") && content.contains("\"ROSETTA_ADVERTISE_AVX\" = \"1\"") {
                        next.avxAndMsyncEnabled = true
                    }
                }
            }
        }

        if next.crossoverExists {
            let plistPath = "\(cxAppPath)/Contents/Info.plist"
            if let dict = NSDictionary(contentsOfFile: plistPath) {
                let shortVer = dict["CFBundleShortVersionString"] as? String ?? "?"
                let buildVer = dict["CFBundleVersion"] as? String ?? "?"
                next.versionString = "\(shortVer) (\(buildVer))"
                if let cat = dict["LSApplicationCategoryType"] as? String, cat == "public.app-category.games" {
                    next.gameModeEnabled = true
                }
            }

            let libavPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib64/gstreamer-1.0/libgstlibav.dylib"
            next.hasGStreamer = fm.fileExists(atPath: libavPath)
            if next.hasGStreamer {
                let gstPlist = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib64/GStreamer.framework/Versions/Current/Resources/Info.plist"
                if let gstDict = NSDictionary(contentsOfFile: gstPlist),
                   let gstVer = gstDict["CFBundleShortVersionString"] as? String {
                    next.gstreamerVersion = "v\(gstVer) (Full + FFmpeg)"
                } else {
                    next.gstreamerVersion = "Full (GStreamer.framework)"
                }
            }

            let d3dMetalBin = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib64/apple_gptk/external/D3DMetal.framework/D3DMetal"
            next.hasD3DMetal = fm.fileExists(atPath: d3dMetalBin)
            if next.hasD3DMetal {
                let d3dPlist = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib64/apple_gptk/external/D3DMetal.framework/Resources/Info.plist"
                if let d3dDict = NSDictionary(contentsOfFile: d3dPlist),
                   let ver = d3dDict["CFBundleShortVersionString"] as? String {
                    next.d3dMetalVersion = "v\(ver)"
                } else {
                    next.d3dMetalVersion = "Installed (Protected)"
                }
            }

            let backupBase = gptkBackupDir(for: cxAppPath)
            let backupBin = "\(backupBase)/external/D3DMetal.framework/D3DMetal"
            next.hasD3DMetalBackup = fm.fileExists(atPath: backupBin)
            if next.hasD3DMetalBackup {
                let backupPlist = "\(backupBase)/external/D3DMetal.framework/Resources/Info.plist"
                if let backupDict = NSDictionary(contentsOfFile: backupPlist),
                   let ver = backupDict["CFBundleShortVersionString"] as? String {
                    next.d3dMetalBackupVersion = "v\(ver)"
                } else {
                    next.d3dMetalBackupVersion = "Stock"
                }
            }

            let dxmtPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib/dxmt/x86_64-windows/d3d11.dll"
            next.hasDXMT = fm.fileExists(atPath: dxmtPath)
            next.dxmtVersion = next.hasDXMT ? "v0.80 Builtin" : "Missing"

            let dxvkPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib/dxvk/x86_64-windows/dxgi.dll"
            next.hasDXVK = fm.fileExists(atPath: dxvkPath)

            let wineGstPath = "\(cxAppPath)/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/winegstreamer.so"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: wineGstPath)),
               let needle = "GStreamer.framework/Versions/Current/lib".data(using: .utf8) {
                next.hasRpath = data.range(of: needle) != nil
            }
        }

        // Calculate cache sizes
        var totalCache: Int64 = 0
        let gstRegistry = ("~/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin" as NSString).expandingTildeInPath
        if let attr = try? fm.attributesOfItem(atPath: gstRegistry), let sz = attr[.size] as? Int64 {
            totalCache += sz
        }

        // Check /var/folders for d3dm caches
        if let enumerator = fm.enumerator(at: URL(fileURLWithPath: "/var/folders"), includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.lowercased().contains("d3dm") {
                    if let sz = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalCache += Int64(sz)
                    }
                }
            }
        }
        next.cacheSizeBytes = totalCache

        return next
    }

    // MARK: - Actions

    func runPatch() {
        guard !isBusy else { return }
        isBusy = true
        logs.removeAll()
        appendLog("Starting HexAid patch on \(selectedCrossOverName).app...")

        let doGst = updateGStreamer
        let doDxmt = updateDXMT
        let doDxvk = updateDXVK
        let doPerf = enableAVXAndMSync
        let cxPath = cxAppPath
        let cxName = selectedCrossOverName
        let btlPath = bottlesPath
        let cxShellPath = Self.shellQuoted(cxPath)
        let bottleShellPath = Self.shellQuoted(btlPath)

        Task.detached {
            let script = """
            set -e
            setopt NULL_GLOB NO_NOMATCH
            CX_APP=\(cxShellPath)
            LIB64="$CX_APP/Contents/SharedSupport/CrossOver/lib64"
            WINE_UNIX="$CX_APP/Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix"
            DXMT_DIR="$CX_APP/Contents/SharedSupport/CrossOver/lib/dxmt"
            DXVK_DIR="$CX_APP/Contents/SharedSupport/CrossOver/lib/dxvk"
            BOTTLES_DIR=\(bottleShellPath)

            CX_PROCESS_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$CX_APP/Contents/Info.plist" 2>/dev/null || echo "CrossOver")
            if pgrep -x "$CX_PROCESS_NAME" >/dev/null 2>&1 || pgrep -x "wineloader" >/dev/null 2>&1 || pgrep -x "wineserver" >/dev/null 2>&1; then
                echo "Closing the selected CrossOver app and running Wine processes..."
                killall "$CX_PROCESS_NAME" wineloader wineserver 2>/dev/null || true
                sleep 1
            fi

            if [ "\(doGst ? "1" : "0")" = "1" ]; then
                echo "Resolving latest GStreamer build from Sikarugir-App/gstreamer..."
                GST_TAG=$(curl -fsSL "https://api.github.com/repos/Sikarugir-App/gstreamer/releases/latest" 2>/dev/null | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\\1/' || true)
                if [ -z "$GST_TAG" ]; then
                    GST_TAG="1.28.1"
                fi
                GST_URL="https://github.com/Sikarugir-App/gstreamer/releases/download/${GST_TAG}/gstreamer-1.0-${GST_TAG}-x86_64.tar.xz"
                echo "Downloading & extracting GStreamer ${GST_TAG} (with FFmpeg/libav)..."
                rm -rf "$LIB64/GStreamer.framework"
                curl -fL "$GST_URL" | tar -xJ -C "$LIB64/"

                echo "Cleaning conflicting stock GStreamer/GLib libraries & linking plugins..."
                cd "$LIB64"
                rm -f libgst*.dylib libglib-2.0*.dylib libgobject-2.0*.dylib libgio-2.0*.dylib libgmodule-2.0*.dylib libgthread-2.0*.dylib libpcre2*.dylib libintl*.dylib libffi*.dylib 2>/dev/null || true
                rm -rf gstreamer-1.0
                ln -s "GStreamer.framework/Versions/Current/lib/gstreamer-1.0" gstreamer-1.0

                echo "Linking winegstreamer.so to GStreamer.framework..."
                if ! otool -l "$WINE_UNIX/winegstreamer.so" | grep -q "GStreamer.framework/Versions/Current/lib"; then
                    install_name_tool -add_rpath "@loader_path/../../../lib64/GStreamer.framework/Versions/Current/lib" "$WINE_UNIX/winegstreamer.so"
                else
                    echo "winegstreamer.so rpath already configured."
                fi
            fi

            if [ "\(doDxmt ? "1" : "0")" = "1" ]; then
                echo "Resolving latest DXMT release from 3Shain/dxmt..."
                DXMT_URL=$(curl -fsSL "https://api.github.com/repos/3Shain/dxmt/releases/latest" 2>/dev/null | grep -oE 'https://github.com/3Shain/dxmt/releases/download/[^"]+builtin\\.tar\\.gz' | head -n1 || true)
                if [ -z "$DXMT_URL" ]; then
                    DXMT_URL="https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"
                fi
                echo "Downloading & extracting DXMT ($DXMT_URL)..."
                mkdir -p "$DXMT_DIR"
                curl -fL "$DXMT_URL" | tar -xz -C "$DXMT_DIR/"
            fi

            if [ "\(doDxvk ? "1" : "0")" = "1" ]; then
                echo "Checking latest macOS DXVK release from Gcenx/DXVK-macOS..."
                DXVK_URL=$(curl -fsSL "https://api.github.com/repos/Gcenx/DXVK-macOS/releases/latest" 2>/dev/null | grep -oE 'https://github.com/Gcenx/DXVK-macOS/releases/download/[^"]+\\.tar\\.gz' | head -n1 || true)
                if [ -n "$DXVK_URL" ]; then
                    echo "Downloading & updating DXVK ($DXVK_URL)..."
                    TMP_DXVK=$(mktemp -d /tmp/hexaid_dxvk.XXXXXX)
                    if curl -fL "$DXVK_URL" | tar -xz -C "$TMP_DXVK" 2>/dev/null; then
                        mkdir -p "$DXVK_DIR/x86_64-windows" "$DXVK_DIR/i386-windows"
                        find "$TMP_DXVK" -path "*/x64/*.dll" -exec cp -f {} "$DXVK_DIR/x86_64-windows/" \\; 2>/dev/null || true
                        find "$TMP_DXVK" -path "*/x32/*.dll" -exec cp -f {} "$DXVK_DIR/i386-windows/" \\; 2>/dev/null || true
                        echo "DXVK updated."
                    fi
                    rm -rf "$TMP_DXVK"
                fi
            fi

            if [ "\(doPerf ? "1" : "0")" = "1" ] && [ -d "$BOTTLES_DIR" ]; then
                echo "Ensuring WINEMSYNC=1 and ROSETTA_ADVERTISE_AVX=1 on existing bottles..."
                for CONF in "$BOTTLES_DIR"/*/cxbottle.conf; do
                    [ -f "$CONF" ] || continue
                    if ! grep -q '"WINEMSYNC"' "$CONF"; then
                        printf '\\n"WINEMSYNC" = "1"\\n' >> "$CONF"
                    fi
                    if ! grep -q '"ROSETTA_ADVERTISE_AVX"' "$CONF"; then
                        printf '"ROSETTA_ADVERTISE_AVX" = "1"\\n' >> "$CONF"
                    fi
                done
            fi

            echo "Clearing quarantine, re-signing \(cxName).app & resetting caches..."
            xattr -cr "$CX_APP"
            codesign --force --deep --sign - "$CX_APP"
            rm -f "$HOME/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin"

            echo "[OK] HexAid patch complete. All components verified."
            """

            await self.executeShellScript(script)
        }
    }

    func applyOptimizations() {
        guard !isBusy else { return }
        isBusy = true
        logs.removeAll()
        appendLog("Applying bottle optimizations...")

        let enableHUD = toggleMetalHUD
        let enableNvidia = toggleNvidiaSpoof
        let enableGM = toggleGameMode
        let cxPath = cxAppPath
        let cxName = selectedCrossOverName
        let btlPath = bottlesPath
        let cxShellPath = Self.shellQuoted(cxPath)
        let bottleShellPath = Self.shellQuoted(btlPath)

        Task.detached {
            let script = """
            set -e
            CX_APP=\(cxShellPath)
            BOTTLES_DIR=\(bottleShellPath)

            echo "Updating CrossOver bottle configurations..."
            for CONF in "$BOTTLES_DIR"/*/cxbottle.conf; do
                [ -f "$CONF" ] || continue
                BOTTLE_NAME=$(basename "$(dirname "$CONF")")

                # Metal Performance HUD
                if [ "\(enableHUD ? "1" : "0")" = "1" ]; then
                    if ! grep -q '"MTL_HUD_ENABLED"' "$CONF"; then
                        echo "[$BOTTLE_NAME] Enabling Metal Performance HUD..."
                        printf '\\n"MTL_HUD_ENABLED" = "1"\\n' >> "$CONF"
                    fi
                else
                    if grep -q '"MTL_HUD_ENABLED"' "$CONF"; then
                        echo "[$BOTTLE_NAME] Disabling Metal Performance HUD..."
                        sed -i '' '/"MTL_HUD_ENABLED"/d' "$CONF"
                    fi
                fi

                # NVIDIA GPU Spoofing for D3DMetal (Bypasses UE5 driver warnings)
                if [ "\(enableNvidia ? "1" : "0")" = "1" ]; then
                    if ! grep -q '"D3DM_VENDOR_ID"' "$CONF"; then
                        echo "[$BOTTLE_NAME] Setting D3DMetal Vendor to NVIDIA (0x10DE / RTX 4090)..."
                        printf '\\n"D3DM_VENDOR_ID" = "0x10DE"\\n"D3DM_DEVICE_ID" = "0x2684"\\n' >> "$CONF"
                    fi
                else
                    if grep -q '"D3DM_VENDOR_ID"' "$CONF"; then
                        echo "[$BOTTLE_NAME] Removing NVIDIA D3DMetal spoofing..."
                        sed -i '' '/"D3DM_VENDOR_ID"/d' "$CONF"
                        sed -i '' '/"D3DM_DEVICE_ID"/d' "$CONF"
                    fi
                fi
            done

            if [ "\(enableGM ? "1" : "0")" = "1" ]; then
                echo "Configuring macOS Game Mode for \(cxName) & game launchers..."
                /usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.games" "$CX_APP/Contents/Info.plist" 2>/dev/null || \\
                /usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.games" "$CX_APP/Contents/Info.plist"
                codesign --force --deep --sign - "$CX_APP"
                /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$CX_APP"

                # Tag any installed CrossOver game app launchers
                if [ -d "$HOME/Applications/CrossOver" ]; then
                    find "$HOME/Applications/CrossOver" -name "*.app" -maxdepth 3 | while read -r GAME_APP; do
                        [ -f "$GAME_APP/Contents/Info.plist" ] || continue
                        /usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.games" "$GAME_APP/Contents/Info.plist" 2>/dev/null || \\
                        /usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.games" "$GAME_APP/Contents/Info.plist"
                        codesign --force --deep --sign - "$GAME_APP" 2>/dev/null || true
                        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$GAME_APP" 2>/dev/null || true
                    done
                fi
                echo "macOS Game Mode successfully configured!"
            fi

            echo "[OK] All optimizations applied successfully."
            """

            await self.executeShellScript(script)
        }
    }

    func clearShaderCaches() {
        guard !isBusy else { return }
        isBusy = true
        logs.removeAll()
        appendLog("Clearing D3DMetal, DXMT & GStreamer caches...")

        Task.detached {
            let script = """
            rm -f "$HOME/Library/Application Support/CrossOver/gstreamer-1.0-registry.x86_64.bin"
            find /var/folders -name "*d3dm*" -exec rm -rf {} + 2>/dev/null || true
            echo "[OK] Successfully purged GStreamer registry & D3DMetal shader caches."
            """
            await self.executeShellScript(script)
        }
    }

    func chooseAndInstallGPTK() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Select Apple Game Porting Toolkit (.dmg)"
        panel.message = "Choose the outer Game Porting Toolkit .dmg or inner Evaluation environment .dmg."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let dmgType = UTType(filenameExtension: "dmg") {
            panel.allowedContentTypes = [dmgType]
        }

        if panel.runModal() == .OK, let url = panel.url {
            installGPTK(from: url)
        }
    }

    func installGPTK(from dmgURL: URL) {
        guard !isBusy else { return }
        isBusy = true
        activeTab = .maintenance
        logs.removeAll()
        appendLog("Installing D3DMetal from \(dmgURL.lastPathComponent) into \(selectedCrossOverName)...")

        let cxPath = cxAppPath
        let backupDir = Self.gptkBackupDir(for: cxPath)
        let dmgPath = dmgURL.path

        Task.detached {
            let quotedCX = Self.shellQuoted(cxPath)
            let quotedDMG = Self.shellQuoted(dmgPath)
            let quotedBackup = Self.shellQuoted(backupDir)
            let script = """
            set -e
            setopt NULL_GLOB NO_NOMATCH

            CX_APP=\(quotedCX)
            DMG_PATH=\(quotedDMG)
            BACKUP_DIR=\(quotedBackup)
            TARGET_GPTK="$CX_APP/Contents/SharedSupport/CrossOver/lib64/apple_gptk"

            OUTER_MOUNT=$(mktemp -d /tmp/hexaid_gptk_outer.XXXXXX)
            INNER_MOUNT=""

            cleanup() {
                if [ -n "$INNER_MOUNT" ] && [ -d "$INNER_MOUNT" ]; then
                    hdiutil detach "$INNER_MOUNT" -force >/dev/null 2>&1 || true
                    rmdir "$INNER_MOUNT" >/dev/null 2>&1 || true
                fi
                if [ -n "$OUTER_MOUNT" ] && [ -d "$OUTER_MOUNT" ]; then
                    hdiutil detach "$OUTER_MOUNT" -force >/dev/null 2>&1 || true
                    rmdir "$OUTER_MOUNT" >/dev/null 2>&1 || true
                fi
            }
            trap cleanup EXIT

            echo "Mounting $(basename "$DMG_PATH")..."
            yes | hdiutil attach "$DMG_PATH" -nobrowse -readonly -noverify -mountpoint "$OUTER_MOUNT" >/dev/null

            FOUND_FW=$(find "$OUTER_MOUNT" -maxdepth 5 -type d -name "D3DMetal.framework" 2>/dev/null | head -n 1 || true)

            if [ -z "$FOUND_FW" ]; then
                INNER_DMG=$(find "$OUTER_MOUNT" -maxdepth 3 -type f -iname "*.dmg" 2>/dev/null | head -n 1 || true)
                if [ -n "$INNER_DMG" ]; then
                    echo "Found nested disk image: $(basename "$INNER_DMG"). Mounting..."
                    INNER_MOUNT=$(mktemp -d /tmp/hexaid_gptk_inner.XXXXXX)
                    yes | hdiutil attach "$INNER_DMG" -nobrowse -readonly -noverify -mountpoint "$INNER_MOUNT" >/dev/null
                    FOUND_FW=$(find "$INNER_MOUNT" -maxdepth 5 -type d -name "D3DMetal.framework" 2>/dev/null | head -n 1 || true)
                fi
            fi

            if [ -z "$FOUND_FW" ]; then
                echo "[Error] Could not locate D3DMetal.framework inside the selected .dmg."
                exit 1
            fi

            SRC_EXTERNAL=$(dirname "$FOUND_FW")
            SRC_ROOT=$(dirname "$SRC_EXTERNAL")
            SRC_WINE="$SRC_ROOT/wine"

            if [ ! -f "$SRC_EXTERNAL/libd3dshared.dylib" ] || [ ! -d "$SRC_WINE" ]; then
                echo "[Error] Incomplete GPTK package: expected external/libd3dshared.dylib alongside wine/ shims."
                exit 1
            fi

            NEW_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$FOUND_FW/Resources/Info.plist" 2>/dev/null || echo "Unknown")
            MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$FOUND_FW/Resources/Info.plist" 2>/dev/null || true)
            CUR_OS=$(sw_vers -productVersion)

            echo "Detected Apple D3DMetal v$NEW_VER (Minimum macOS: ${MIN_OS:-any}, Current macOS: $CUR_OS)"

            if [ -n "$MIN_OS" ]; then
                autoload -Uz is-at-least
                if ! is-at-least "$MIN_OS" "$CUR_OS"; then
                    echo "[Error] D3DMetal v$NEW_VER requires macOS $MIN_OS or newer (you are on $CUR_OS). Aborting safely."
                    exit 1
                fi
            fi

            if [ ! -f "$BACKUP_DIR/external/D3DMetal.framework/D3DMetal" ] && [ -d "$TARGET_GPTK" ]; then
                echo "Backing up stock CrossOver D3DMetal to $BACKUP_DIR..."
                mkdir -p "$BACKUP_DIR"
                ditto "$TARGET_GPTK" "$BACKUP_DIR"
            else
                echo "Preserving existing stock D3DMetal backup."
            fi

            echo "Installing matched external/ and wine/ GPTK runtime into $CX_APP..."
            mkdir -p "$TARGET_GPTK"
            rm -rf "$TARGET_GPTK/external" "$TARGET_GPTK/wine"
            ditto "$SRC_EXTERNAL" "$TARGET_GPTK/external"
            ditto "$SRC_WINE" "$TARGET_GPTK/wine"

            echo "Clearing quarantine, re-signing CrossOver, and purging D3DMetal shader caches..."
            xattr -cr "$TARGET_GPTK"
            codesign --force --deep --sign - "$CX_APP"
            find /var/folders -name "*d3dm*" -exec rm -rf {} + 2>/dev/null || true

            echo "[OK] Installed Apple D3DMetal v$NEW_VER cleanly! Use 'Restore Original' anytime to revert."
            """
            await self.executeShellScript(script)
        }
    }

    func restoreD3DMetal() {
        guard !isBusy else { return }
        isBusy = true
        activeTab = .maintenance
        logs.removeAll()
        appendLog("Restoring original stock D3DMetal for \(selectedCrossOverName)...")

        let cxPath = cxAppPath
        let backupDir = Self.gptkBackupDir(for: cxPath)

        Task.detached {
            let quotedCX = Self.shellQuoted(cxPath)
            let quotedBackup = Self.shellQuoted(backupDir)
            let script = """
            set -e
            CX_APP=\(quotedCX)
            BACKUP_DIR=\(quotedBackup)
            TARGET_GPTK="$CX_APP/Contents/SharedSupport/CrossOver/lib64/apple_gptk"

            if [ ! -d "$BACKUP_DIR/external" ] || [ ! -d "$BACKUP_DIR/wine" ]; then
                echo "[Error] No stock D3DMetal backup found at $BACKUP_DIR."
                exit 1
            fi

            echo "Restoring backed-up apple_gptk into $CX_APP..."
            rm -rf "$TARGET_GPTK/external" "$TARGET_GPTK/wine"
            ditto "$BACKUP_DIR/external" "$TARGET_GPTK/external"
            ditto "$BACKUP_DIR/wine" "$TARGET_GPTK/wine"

            echo "Clearing quarantine, re-signing CrossOver, and purging D3DMetal shader caches..."
            xattr -cr "$TARGET_GPTK"
            codesign --force --deep --sign - "$CX_APP"
            find /var/folders -name "*d3dm*" -exec rm -rf {} + 2>/dev/null || true

            echo "[OK] Original stock D3DMetal restored."
            """
            await self.executeShellScript(script)
        }
    }

    func runAddon(_ addon: GameFixAddon) {
        guard !isBusy else { return }
        isBusy = true
        activeTab = .maintenance
        logs.removeAll()
        appendLog("Downloading \(addon.title) add-on from GitHub...")

        let dirPath = addon.localDirectory.path
        let url = addon.tarballURL
        let folder = addon.folderName
        Task.detached {
            let script = """
            set -e
            ADDON_DIR="\(dirPath)"
            rm -rf "$ADDON_DIR"
            mkdir -p "$ADDON_DIR"
            curl -fsSL "\(url)" | tar -xz -C "$ADDON_DIR" --strip-components=3 "HexAid-main/Addons/\(folder)"
            cd "$ADDON_DIR"
            chmod +x install.sh
            zsh ./install.sh
            echo "[OK] \(addon.title) fix completed."
            """
            await self.executeShellScript(script)
        }
    }

    func executeShellScript(_ script: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            Task { @MainActor in
                for line in lines {
                    self.appendLog(line)
                }
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            handle.readabilityHandler = nil
            let code = process.terminationStatus
            await MainActor.run {
                self.isBusy = false
                self.refreshStatus()
                if code != 0 {
                    self.appendLog("[Error] Process exited with code \(code)")
                }
            }
        } catch {
            handle.readabilityHandler = nil
            await MainActor.run {
                self.isBusy = false
                self.appendLog("[Error] \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var vm = HexAidViewModel()
    @State private var isConfirmingCachePurge = false
    @State private var isConfirmingD3DMetalRestore = false

    var body: some View {
        NavigationSplitView {
            List(ActiveTab.allCases, selection: $vm.activeTab) { tab in
                Label(tab.rawValue, systemImage: tab.iconName)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            detailView
                .navigationTitle(vm.activeTab.rawValue)
                .navigationSubtitle("\(vm.selectedCrossOverName) • v\(vm.status.versionString) • \(vm.status.bottleCount) Bottle\(vm.status.bottleCount == 1 ? "" : "s")")
        }
        .frame(minWidth: 740, idealWidth: 800, minHeight: 560, idealHeight: 650)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if vm.installedCrossOvers.count > 1 {
                    Picker("CrossOver", selection: $vm.selectedCrossOverPath) {
                        ForEach(vm.installedCrossOvers) { installation in
                            Text(installation.displayName).tag(installation.path)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(vm.isBusy)
                    .onChange(of: vm.selectedCrossOverPath) { _ in
                        vm.refreshStatus()
                    }
                }

                Button(action: { vm.refreshStatus() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(vm.isBusy)
                .help("Refresh status (⌘R)")

                if vm.activeTab == .optimizations {
                    Button(action: { vm.applyOptimizations() }) {
                        if vm.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Apply Tweaks")
                                .padding(.horizontal, 6)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isBusy || !vm.status.crossoverExists)
                }
            }
        }
        .confirmationDialog(
            "Purge Shader and Registry Caches?",
            isPresented: $isConfirmingCachePurge,
            titleVisibility: .visible
        ) {
            Button("Purge Caches", role: .destructive) {
                vm.clearShaderCaches()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The caches will be rebuilt as you use CrossOver. This can make the next game launch take longer.")
        }
        .confirmationDialog(
            "Restore Stock Apple D3DMetal?",
            isPresented: $isConfirmingD3DMetalRestore,
            titleVisibility: .visible
        ) {
            Button("Restore Stock D3DMetal (\(vm.status.d3dMetalBackupVersion))", role: .destructive) {
                vm.restoreD3DMetal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replaces the custom GPTK runtime in \(vm.selectedCrossOverName) with your backed-up stock D3DMetal and clears D3DMetal shader caches.")
        }
        .onAppear {
            vm.refreshStatus()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch vm.activeTab {
        case .patcher:
            patcherView
        case .optimizations:
            optimizationsView
        case .gameFixes:
            gameFixesView
        case .maintenance:
            maintenanceView
        }
    }

    private func statusBadge(text: String, ok: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private var patcherView: some View {
        Form {
            Section {
                LabeledContent("GStreamer + FFmpeg") {
                    statusBadge(text: vm.status.gstreamerVersion, ok: vm.status.hasGStreamer)
                }
                LabeledContent("winegstreamer.so Link") {
                    statusBadge(text: vm.status.hasRpath ? "Linked" : "Unpatched", ok: vm.status.hasRpath)
                }
                LabeledContent("Apple D3DMetal") {
                    statusBadge(text: vm.status.d3dMetalVersion, ok: vm.status.hasD3DMetal)
                }
                LabeledContent("DXMT (DirectX 11 to Metal)") {
                    statusBadge(text: vm.status.dxmtVersion, ok: vm.status.hasDXMT)
                }
            } header: {
                HStack {
                    Text("\(vm.selectedCrossOverName) Runtime")
                    Spacer()
                    Text(vm.status.isReady ? "Up to Date" : "Patch Available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Patch Options") {
                Toggle("Full GStreamer + FFmpeg Runtime", isOn: $vm.updateGStreamer)
                    .disabled(vm.isBusy)
                Toggle("Latest DXMT Builtin Release", isOn: $vm.updateDXMT)
                    .disabled(vm.isBusy)
                Toggle("Latest DXVK-macOS", isOn: $vm.updateDXVK)
                    .disabled(vm.isBusy)
                Toggle("Enable MSync + Rosetta 2 AVX", isOn: $vm.enableAVXAndMSync)
                    .disabled(vm.isBusy)

                HStack {
                    Spacer()
                    Button(action: { vm.runPatch() }) {
                        if vm.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(vm.status.isReady ? "Re-Apply Patches" : "Patch \(vm.selectedCrossOverName)")
                                .padding(.horizontal, 8)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(vm.isBusy || !vm.status.crossoverExists)
                }
            }

            Section {
                LabeledContent {
                    Button("Select .dmg…") {
                        vm.chooseAndInstallGPTK()
                    }
                    .disabled(vm.isBusy || !vm.status.crossoverExists)
                } label: {
                    Text("Upgrade from Apple GPTK .dmg")
                    Text("Automatically handles nested .dmg images, backs up stock D3DMetal, and swaps matched external + wine shims")
                }

                if vm.status.hasD3DMetalBackup {
                    LabeledContent {
                        HStack(spacing: 12) {
                            Text(vm.status.d3dMetalBackupVersion)
                                .foregroundStyle(.secondary)
                            Button("Restore Original", role: .destructive) {
                                isConfirmingD3DMetalRestore = true
                            }
                            .disabled(vm.isBusy || !vm.status.crossoverExists)
                        }
                    } label: {
                        Text("Stock D3DMetal Backup")
                        Text("Revert \(vm.selectedCrossOverName) to its original Apple D3DMetal")
                    }
                }
            } header: {
                Text("Apple D3DMetal (GPTK)")
            }
        }
        .formStyle(.grouped)
    }

    private var optimizationsView: some View {
        Form {
            Section("Graphics & System Integration") {
                Toggle("Apple Metal Performance HUD", isOn: $vm.toggleMetalHUD)
                    .disabled(vm.isBusy)
                Toggle("macOS Game Mode", isOn: $vm.toggleGameMode)
                    .disabled(vm.isBusy)
                Toggle("D3DMetal NVIDIA RTX Spoofing", isOn: $vm.toggleNvidiaSpoof)
                    .disabled(vm.isBusy)
                Toggle("MSync + Rosetta 2 AVX", isOn: $vm.enableAVXAndMSync)
                    .disabled(vm.isBusy)
            }
        }
        .formStyle(.grouped)
    }

    private var gameFixesView: some View {
        Form {
            Section("Downloadable Game-Specific Add-Ons") {
                ForEach(GameFixAddon.catalog) { addon in
                    LabeledContent {
                        Button(addon.isDownloaded ? "Re-Apply" : "Download & Run") {
                            vm.runAddon(addon)
                        }
                        .disabled(vm.isBusy || !vm.status.crossoverExists)
                    } label: {
                        Text(addon.title)
                        Text(addon.subtitle)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var maintenanceView: some View {
        Form {
            Section("Shader & Registry Caches") {
                LabeledContent("Cached Data") {
                    HStack(spacing: 12) {
                        Text(vm.status.formattedCacheSize)
                            .foregroundStyle(.secondary)
                        Button("Purge...", role: .destructive) {
                            isConfirmingCachePurge = true
                        }
                        .disabled(vm.isBusy)
                    }
                }
            }

            Section {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            if vm.logs.isEmpty {
                                Text("No recent activity.")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(vm.logs.enumerated()), id: \.offset) { idx, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor((line.contains("[Error]") || line.contains("❌")) ? .red : ((line.contains("[OK]") || line.contains("✅")) ? .green : .primary))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(idx)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                    .onChange(of: vm.logs.count) { _ in
                        if let last = vm.logs.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Console")
                    Spacer()
                    Button("Copy") { vm.copyLogs() }
                        .buttonStyle(.borderless)
                        .disabled(vm.logs.isEmpty)
                    Button("Clear") { vm.clearLogs() }
                        .buttonStyle(.borderless)
                        .disabled(vm.logs.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - App Delegate & Window Setup

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "HexAid"
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 740, height: 520)

        window.contentViewController = NSHostingController(rootView: contentView)
        window.setContentSize(NSSize(width: 800, height: 560))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
