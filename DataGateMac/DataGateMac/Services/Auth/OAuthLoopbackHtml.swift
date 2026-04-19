//
//  OAuthLoopbackHtml.swift
//  DataGateMac
//
//  Branded HTML for the Google OAuth loopback tab — aligned with DataGateLinux
//  `GoogleAuthHelper.cpp` (oauthLoopbackPageCss / oauthSuccessHtml / oauthGoogleErrorHtml).
//

import Foundation

enum OAuthLoopbackHtml {
    /// CSS variables + layout (same palette as Linux `BrandColors` + `oauthLoopbackPageCss`).
    private static var loopbackPageCss: String {
        let darkBgDefault = "#0d1117"
        let darkBgMuted = "#161b22"
        let darkBgSubtle = "#21262d"
        let darkTextDefault = "#c9d1d9"
        let darkTextMuted = "#8b949e"
        let darkAccentFg = "#58a6ff"
        let darkAccentEmphasis = "#1f6feb"
        let darkBorder = "#30363d"
        let darkDanger = "#f85149"
        let darkSuccess = "#3fb950"
        let lightBgDefault = "#f6f8fa"
        let lightBgMuted = "#ffffff"
        let lightBgSubtle = "#f6f8fa"
        let lightTextDefault = "#24292f"
        let lightTextMuted = "#656d76"
        let lightAccentFg = "#0969da"
        let lightBorder = "#d0d7de"
        return """
        :root{--bg-default:\(darkBgDefault);--bg-muted:\(darkBgMuted);--bg-subtle:\(darkBgSubtle);\
        --text-default:\(darkTextDefault);--text-muted:\(darkTextMuted);--accent-fg:\(darkAccentFg);\
        --accent-emphasis:\(darkAccentEmphasis);--border-default:\(darkBorder);\
        --danger-fg:\(darkDanger);--success-fg:\(darkSuccess);}
        @media (prefers-color-scheme:light){:root{\
        --bg-default:\(lightBgDefault);--bg-muted:\(lightBgMuted);--bg-subtle:\(lightBgSubtle);\
        --text-default:\(lightTextDefault);--text-muted:\(lightTextMuted);--accent-fg:\(lightAccentFg);\
        --accent-emphasis:\(lightAccentFg);--border-default:\(lightBorder);}}
        *{box-sizing:border-box;}
        html{font-size:16px;-webkit-font-smoothing:antialiased;}
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','Noto Sans',Helvetica,Arial,sans-serif;\
        background:var(--bg-default);color:var(--text-default);min-height:100vh;margin:0;\
        display:flex;align-items:center;justify-content:center;padding:24px;line-height:1.5;}
        .oauth-wrap{width:100%;max-width:480px;}
        .oauth-card{background:var(--bg-muted);border:1px solid var(--border-default);border-radius:8px;\
        padding:32px 28px 28px;text-align:center;\
        box-shadow:0 8px 24px rgba(1,4,9,.4);}
        @media (prefers-color-scheme:light){.oauth-card{box-shadow:0 8px 24px rgba(31,35,40,.1);}}
        .brand{font-size:1.0625rem;font-weight:600;color:var(--text-default);margin-bottom:20px;}
        h1{font-size:1.25rem;font-weight:600;margin:0 0 12px;line-height:1.35;color:var(--text-default);}
        .oauth-main p{font-size:.95rem;color:var(--text-muted);margin:0;line-height:1.55;}
        .ok{width:64px;height:64px;margin:0 auto 20px;border-radius:50%;background:var(--bg-subtle);\
        color:var(--success-fg);display:flex;align-items:center;justify-content:center;font-size:32px;font-weight:600;}
        .bad{width:64px;height:64px;margin:0 auto 20px;border-radius:50%;background:var(--bg-subtle);\
        color:var(--danger-fg);display:flex;align-items:center;justify-content:center;font-size:30px;font-weight:600;}
        .oauth-detail{margin-top:16px;font-size:.85rem;color:var(--text-muted);word-break:break-word;}
        .oauth-footer{margin-top:24px;padding-top:20px;border-top:1px solid var(--border-default);text-align:center;}
        .oauth-more-title{font-weight:600;font-size:.9375rem;color:var(--text-default);margin:14px 0 8px;}
        .oauth-muted{font-size:.8125rem;color:var(--text-muted);margin:0 0 8px;line-height:1.45;}
        .oauth-line{margin:6px 0;font-size:.875rem;}
        .oauth-a{color:var(--accent-fg);text-decoration:none;}
        .oauth-a:hover{text-decoration:underline;}
        """
    }

    private static let siteUrl = "https://datagateapp.com/"
    private static let downloadUrl = "https://datagateapp.com/download"

    private static func htmlFooter() -> String {
        let more = L10n.tr("oauth_footer_more", "More apps")
        let hint = L10n.tr("oauth_footer_hint", "You can download other DataGate apps for your devices from the website:")
        return """
        <footer class="oauth-footer" role="contentinfo">\
        <p class="oauth-line"><a class="oauth-a" href="\(siteUrl)" rel="noopener noreferrer">\(siteUrl)</a></p>\
        <p class="oauth-more-title">\(more.htmlEscapedForAttributeBody())</p>\
        <p class="oauth-muted">\(hint.htmlEscapedForAttributeBody())</p>\
        <p class="oauth-line"><a class="oauth-a" href="\(downloadUrl)" rel="noopener noreferrer">\(downloadUrl)</a></p>\
        </footer>
        """
    }

    private static func shell(innerBody: String) -> String {
        """
        <!DOCTYPE html><html lang="en"><head>\
        <meta charset="utf-8">\
        <meta name="viewport" content="width=device-width,initial-scale=1">\
        <meta name="color-scheme" content="dark light">\
        <meta name="theme-color" content="#0d1117">\
        <title>\(L10n.tr("oauth_page_title", "DataGate").htmlEscapedForAttributeBody())</title><style>\
        \(loopbackPageCss)</style></head><body><div class="oauth-wrap"><div class="oauth-card">\
        \(innerBody)\(htmlFooter())</div></div></body></html>
        """
    }

    static func successDocument() -> String {
        let h = L10n.tr("oauth_success_title", "You're signed in")
        let p = L10n.tr("oauth_success_subtitle", "You can close this tab and return to the DataGate app.")
        return shell(innerBody: """
        <div class="brand">\(L10n.tr("oauth_page_brand", "DataGate").htmlEscapedForAttributeBody())</div>\
        <div class="oauth-main"><div class="ok">✓</div><h1>\(h.htmlEscapedForAttributeBody())</h1><p>\(p.htmlEscapedForAttributeBody())</p></div>
        """)
    }

    static func waitingDocument() -> String {
        let h = L10n.tr("oauth_wait_title", "DataGate sign-in server is running.")
        let p = L10n.tr("oauth_wait_subtitle", "Return to the browser tab that asked you to sign in.")
        return shell(innerBody: """
        <div class="brand">\(L10n.tr("oauth_page_brand", "DataGate").htmlEscapedForAttributeBody())</div>\
        <div class="oauth-main"><h1>\(h.htmlEscapedForAttributeBody())</h1><p>\(p.htmlEscapedForAttributeBody())</p></div>
        """)
    }

    static func googleErrorDocument(errorCode: String, errorDescription: String) -> String {
        let h = L10n.tr("oauth_error_title", "Sign-in did not complete")
        let hint = L10n.tr("oauth_error_subtitle", "You can close this tab and try again from DataGate.")
        let detail = "\(errorCode) — \(errorDescription)"
        return shell(innerBody: """
        <div class="brand">\(L10n.tr("oauth_page_brand", "DataGate").htmlEscapedForAttributeBody())</div>\
        <div class="oauth-main"><div class="bad">✕</div><h1>\(h.htmlEscapedForAttributeBody())</h1>\
        <p>\(hint.htmlEscapedForAttributeBody())</p>\
        <p class="oauth-detail">\(detail.htmlEscapedForAttributeBody())</p></div>
        """)
    }
}

private extension String {
    /// Minimal escaping for text placed inside HTML body text nodes.
    func htmlEscapedForAttributeBody() -> String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
