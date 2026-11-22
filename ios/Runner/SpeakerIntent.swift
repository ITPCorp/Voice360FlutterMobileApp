// AVAudioSession can temporarily report Receiver after a successful speaker
// override. Keep the call's selected route separate from the observed ports.
struct SpeakerIntent {
  private(set) var speakerWanted = false
  private var selected = false

  mutating func select(_ on: Bool) {
    selected = true
    speakerWanted = on
  }

  mutating func followDevice() {
    self = SpeakerIntent()
  }

  mutating func displayRoute(_ output: String?) -> String? {
    if !selected {
      if let output = output { speakerWanted = output == "speaker" }
      return output
    }
    if speakerWanted { return "speaker" }
    return output == "speaker" ? "earpiece" : output
  }

  // An override notification has no sender. While the system call controls
  // are up, a settled transition from another port is the user's selection.
  // A category/configuration reset or our own override echo is not a tap.
  mutating func settle(reason: String, previous: String?, output: String?,
                       ownOverride: Bool, systemControls: Bool) -> Bool {
    guard let output = output else { return false }
    if reason == "override", !ownOverride,
       systemControls || (previous != output && output != "earpiece") {
      select(output == "speaker")
      return false
    }
    if !selected { speakerWanted = output == "speaker"; return false }
    if ownOverride || !speakerWanted { return false }
    switch reason {
    case "categoryChange", "routeConfigurationChange", "didActivate":
      return true
    case "override":
      return output != "speaker"
    default:
      return false
    }
  }
}
