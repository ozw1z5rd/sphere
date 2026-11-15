import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            brainIcon

            VStack(spacing: 4) {
                Text("Sphere")
                    .font(.system(size: 28, weight: .bold))
                Text("Assistente AI locale per macOS")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Versione \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Sphere connette modelli LLM locali o remoti a tool MCP, con accesso a file, schermo e rete mediato da permessi espliciti.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            license

            Spacer(minLength: 4)

            companyLogo
        }
        .padding(28)
        .frame(width: 470, height: 620)
    }

    /// The app icon (circuit brain), shown large as the About hero image.
    private var brainIcon: some View {
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(26)
                    .foregroundStyle(.green)
            }
        }
        .frame(width: 150, height: 150)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        .accessibilityLabel("Cervello circuitale, icona di Sphere")
    }

    private var license: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Licenza Creative Commons BY-NC-SA 4.0")
                .font(.caption.weight(.semibold))
            Text("Il codice non può essere usato per fini commerciali. Puoi distribuirlo citando la fonte (Sphere) e condividendo le opere derivate con la stessa licenza.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Attribuzione · Non commerciale · Condividi allo stesso modo")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var companyLogo: some View {
        VStack(spacing: 6) {
            Group {
                if let image = Self.logoImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay(Text("Logo").font(.caption).foregroundStyle(.secondary))
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("© \(year) Home Computer Group")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    static var logoImage: NSImage? {
        var candidates: [URL] = []
        if let url = Bundle.main.url(forResource: "CompanyLogo", withExtension: "png") {
            candidates.append(url)
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Sphere_SphereApp.bundle/CompanyLogo.png"))
        }
        let executableDirectory = Bundle.main.bundleURL.deletingLastPathComponent()
        candidates.append(executableDirectory.appendingPathComponent("Sphere_SphereApp.bundle/CompanyLogo.png"))
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/SphereApp/Resources/CompanyLogo.png")
        )

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "\(short) (\(build))"
        }
        return short
    }

    private var year: String {
        String(Calendar.current.component(.year, from: Date()))
    }
}
