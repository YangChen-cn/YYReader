enum HTMLChallengeDetector {
    static func isChallenge(_ html: String) -> Bool {
        let sample = html.lowercased()
        return sample.contains("cf-chl-")
            || sample.contains("cloudflare challenge")
            || sample.contains("<title>just a moment")
            || sample.contains("enable javascript and cookies to continue")
    }
}
