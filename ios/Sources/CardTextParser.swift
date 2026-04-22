import Foundation

enum CardTextParser {
  static func digitsOnly(_ value: String) -> String {
    value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
  }

  // OCR often confuses certain letters with digits (O/0, I/1, etc).
  // Only used for PAN extraction; do not apply to holder name.
  static func normalizeForPANSearch(_ value: String) -> String {
    value
      .uppercased()
      .replacingOccurrences(of: "O", with: "0")
      .replacingOccurrences(of: "Q", with: "0")
      .replacingOccurrences(of: "D", with: "0")
      .replacingOccurrences(of: "I", with: "1")
      .replacingOccurrences(of: "L", with: "1")
      .replacingOccurrences(of: "Z", with: "2")
      .replacingOccurrences(of: "S", with: "5")
      .replacingOccurrences(of: "G", with: "6")
      .replacingOccurrences(of: "T", with: "7")
      .replacingOccurrences(of: "B", with: "8")
  }

  // Luhn for PAN validation
  static func luhnCheck(_ pan: String) -> Bool {
    let digits = Array(pan)
    if digits.count < 12 { return false }
    var sum = 0
    var shouldDouble = false
    for ch in digits.reversed() {
      guard let d = Int(String(ch)) else { return false }
      var digit = d
      if shouldDouble {
        digit *= 2
        if digit > 9 { digit -= 9 }
      }
      sum += digit
      shouldDouble.toggle()
    }
    return sum % 10 == 0
  }

  static func redact(_ pan: String) -> String {
    let digits = digitsOnly(pan)
    guard digits.count >= 4 else { return "" }
    let last4 = String(digits.suffix(4))
    // Keep formatting predictable for UI/state; do not reveal length.
    return "•••• •••• •••• \(last4)"
  }

  static func extract(from lines: [String]) -> CardScanResult? {
    let trimmed = lines
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let pan = bestPAN(in: trimmed)
    let expiry = bestExpiry(in: trimmed) // "MM/YY" or ""
    let name = bestName(in: trimmed) // "JOHN DOE" or ""

    if pan.isEmpty, expiry.isEmpty, name.isEmpty { return nil }

    return CardScanResult(
      cardNumber: pan,
      cardNumberRedacted: redact(pan),
      cardHolderName: name,
      expirationDate: expiry
    )
  }

  private static func bestPAN(in lines: [String]) -> String {
    // Search per-line and also concatenated to handle OCR line breaks.
    let candidates = lines + [lines.joined(separator: " ")]
    var bestValid: (digits: String, score: Int)? = nil
    var bestFallback: (digits: String, score: Int)? = nil
    for text in candidates {
      let normalized = normalizeForPANSearch(text)
      for match in findPANCandidates(in: normalized) {
        let digits = digitsOnly(match)
        if digits.count < 12 || digits.count > 19 { continue }
        let score = panScore(raw: match, digits: digits)

        if luhnCheck(digits) {
          if bestValid == nil || score > bestValid!.score {
            bestValid = (digits, score)
          }
        } else {
          if bestFallback == nil || score > bestFallback!.score {
            bestFallback = (digits, score)
          }
        }
      }
    }
    return bestValid?.digits ?? bestFallback?.digits ?? ""
  }

  private static func findPANCandidates(in text: String) -> [String] {
    // Matches "4242 4242 4242 4242", "4242424242424242", "4242-4242-..."
    let pattern = "(?:\\d[\\s\\-]?){12,23}"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
      .map { ns.substring(with: $0.range) }
  }

  private static func panScore(raw: String, digits: String) -> Int {
    // Prefer typical card lengths, and 4-digit group formatting if present.
    var score = 0
    let len = digits.count
    if len == 16 { score += 30 }
    if len == 15 { score += 20 }
    if len == 14 || len == 13 { score += 10 }

    // Formatting hints
    if raw.range(of: "\\d{4}[\\s\\-]\\d{4}[\\s\\-]\\d{4}[\\s\\-]\\d{3,4}", options: .regularExpression) != nil {
      score += 25
    } else if raw.range(of: "\\d{4}[\\s\\-]\\d{4}", options: .regularExpression) != nil {
      score += 10
    }
    if raw.contains("-") { score += 2 }
    if raw.contains(" ") { score += 2 }

    // Slight preference to longer (but within bounds).
    score += min(19, max(12, len)) - 12
    return score
  }

  private static func bestExpiry(in lines: [String]) -> String {
    // OCR may output expiry as "12/26", "12-2026", or digits-only like "1226"/"12 26".
    // We intentionally ignore candidates embedded in long digit strings (e.g. PAN).
    let pattern = "\\b(0?[1-9]|1[0-2])\\s*[/\\-]\\s*(\\d{2,4})\\b"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return "" }

    for line in lines {
      // 1) Prefer explicit separators (/, -)
      let ns = line as NSString
      let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: ns.length))
      for m in matches {
        if m.numberOfRanges != 3 { continue }
        let mm = ns.substring(with: m.range(at: 1))
        let yyRaw = ns.substring(with: m.range(at: 2))
        let month = Int(mm) ?? 0
        var year = Int(yyRaw) ?? 0
        if month < 1 || month > 12 { continue }
        if year < 100 { year += 2000 }
        if year < 2000 || year > 2100 { continue }
        let yy = String(year).suffix(2)
        return String(format: "%02d/%@", month, String(yy))
      }

      // 2) Digits-only fallback: "MMYY" / "MM YYYY" -> digitsOnly length 4 or 6.
      let digits = digitsOnly(line)
      if digits.count != 4 && digits.count != 6 { continue }

      let mmStr = String(digits.prefix(2))
      let yyStr = digits.count == 4 ? String(digits.suffix(2)) : String(digits.suffix(4))
      let month = Int(mmStr) ?? 0
      var year = Int(yyStr) ?? 0
      if month < 1 || month > 12 { continue }
      if year < 100 { year += 2000 }
      if year < 2000 || year > 2100 { continue }
      let yy = String(year).suffix(2)
      return String(format: "%02d/%@", month, String(yy))
    }

    return ""
  }

  private static func bestName(in lines: [String]) -> String {
    // Heuristic: longest line with 2+ words, no digits, avoids common labels.
    let stopWords: [String] = [
      "VALID", "THRU", "THROUGH", "FROM", "UNTIL", "EXPIRES", "EXP", "MONTH", "YEAR",
      "CVV", "CVC", "SECURITY", "CARD", "NUMBER", "BANK", "PLATINUM", "DEBIT", "CREDIT"
    ]

    var best = ""
    var bestScore = -1

    for line in lines {
      let cleaned = line
        .replacingOccurrences(of: "[^A-Za-z\\s.'\\-]", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

      if cleaned.isEmpty { continue }
      if cleaned.count < 5 { continue }
      if cleaned.range(of: "\\d", options: .regularExpression) != nil { continue }

      let upper = cleaned.uppercased()
      if stopWords.contains(where: { upper.contains($0) }) { continue }

      let parts = upper.split(separator: " ").map(String.init)
      if parts.count < 2 { continue }
      if parts.contains(where: { $0.count < 2 }) { continue }

      // Score: prefer longer and more "name-like".
      let score = cleaned.count + parts.count * 2
      if score > bestScore {
        bestScore = score
        best = upper
      }
    }

    return best
  }
}
