import Foundation

/// What a page says about itself, read from the browser rather than the screen.
struct PageContent: Codable, Sendable {
    struct Link: Codable, Sendable {
        var href: String
        var text: String
        var label: String
        /// The innerText of the block the link sits in — for a class list, the
        /// whole card: name, section, teacher.
        var card: String
    }

    var url: String
    var title: String
    var links: [Link]
    var text: String
}

/// Asks the browser what is actually on the page.
///
/// A screenshot can only show what fits: Classroom clips long class names and
/// there is no way to recover them from pixels. The page itself still holds the
/// whole string, so where the browser will say, Locker asks — no Google API, no
/// account, nothing leaving the Mac.
enum BrowserDOM {

    enum Failure: LocalizedError {
        case notABrowser
        case javaScriptDisabled(String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notABrowser:
                "That window isn't a browser Locker can read."
            case .javaScriptDisabled(let browser):
                "\(browser) won't let Locker read the page yet. In \(browser), choose View › Developer › Allow JavaScript from Apple Events, then try again. Capturing the window still works without it."
            case .unreadable:
                "Nothing could be read from that page."
            }
        }
    }

    /// Deliberately attribute-light: it collects links with their text and the
    /// block around them, rather than reaching for particular class names, so a
    /// redesign of the site changes what is found rather than breaking it.
    static let script = """
        (function(){
          var out = {url: location.href, title: document.title, links: [], text: ''};
          var seen = {};
          var anchors = document.querySelectorAll('a[href]');
          for (var i = 0; i < anchors.length && out.links.length < 200; i++) {
            var a = anchors[i];
            var text = (a.innerText || '').trim();
            var label = a.getAttribute('aria-label') || a.getAttribute('title') || '';
            if (!text && !label) continue;
            var key = a.href + '|' + text;
            if (seen[key]) continue;
            seen[key] = 1;
            var box = a.closest('li') || a.closest('[role=listitem]') || a.parentElement;
            out.links.push({
              href: a.href,
              text: text.slice(0, 200),
              label: label.slice(0, 200),
              card: box ? (box.innerText || '').slice(0, 400) : ''
            });
          }
          out.text = (document.body.innerText || '').slice(0, 20000);
          return JSON.stringify(out);
        })()
        """

    static func read(_ window: CapturableWindow, tab: BrowserTab?) async throws -> PageContent {
        guard let kind = BrowserTabs.Kind(bundleIdentifier: window.bundleIdentifier) else {
            throw Failure.notABrowser
        }
        if let tab { await BrowserTabs.focus(tab, in: window) }

        let source = appleScript(for: kind)
        let result = await BrowserTabs.runScript(source)

        switch result {
        case .failure(let message):
            throw failure(for: message, browser: kind.applicationName)
        case .success(let json):
            guard let data = json.data(using: .utf8),
                  let content = try? JSONDecoder().decode(PageContent.self, from: data) else {
                throw Failure.unreadable
            }
            return content
        }
    }

    /// Turns the browser's complaint into something actionable.
    ///
    /// The one that matters reads "Executing JavaScript through AppleScript is
    /// turned off", which is a switch the student can flip rather than a dead end.
    static func failure(for message: String, browser: String) -> Failure {
        message.lowercased().contains("javascript")
            ? .javaScriptDisabled(browser)
            : .unreadable
    }

    private static func appleScript(for kind: BrowserTabs.Kind) -> String {
        // The JavaScript is embedded as an AppleScript string, so its own quotes
        // have to survive one level of escaping.
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        switch kind {
        case .safari:
            return """
            tell application "Safari" to do JavaScript "\(escaped)" in front document
            """
        case .chromium(let name):
            return """
            tell application "\(name)" to execute front window's active tab javascript "\(escaped)"
            """
        }
    }
}
