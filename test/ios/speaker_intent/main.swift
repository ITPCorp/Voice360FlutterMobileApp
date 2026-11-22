// Run with swiftc ios/Runner/SpeakerIntent.swift test/ios/speaker_intent/main.swift.
var intent = SpeakerIntent()
func change(_ reason: String, _ previous: String?, _ output: String?,
            own: Bool = false, system: Bool = false) -> Bool {
  intent.settle(reason: reason, previous: previous, output: output,
                ownOverride: own, systemControls: system)
}
precondition(intent.displayRoute("earpiece") == "earpiece")
intent.select(!intent.speakerWanted)
precondition(!change("override", "earpiece", "speaker", own: true))
for reason in ["categoryChange", "routeConfigurationChange", "override", "didActivate"] {
  precondition(change(reason, "speaker", "earpiece"))
  precondition(intent.displayRoute("earpiece") == "speaker")
}
intent.select(!intent.speakerWanted)
precondition(intent.displayRoute("speaker") == "earpiece")
precondition(!change("override", "speaker", "earpiece", own: true))

// Case O: both directions through system call controls, including delayed echoes.
precondition(!change("override", "earpiece", "speaker", system: true))
precondition(intent.speakerWanted)
precondition(!change("override", "speaker", "earpiece", system: true))
precondition(!intent.speakerWanted)
intent.select(true)
precondition(!change("override", "speaker", "earpiece", own: true, system: true))
precondition(intent.speakerWanted)
for reason in ["newDeviceAvailable", "oldDeviceUnavailable"] {
  intent.followDevice()
  precondition(!change(reason, "speaker", "bluetooth"))
  precondition(intent.displayRoute("bluetooth") == "bluetooth")
  precondition(!change("categoryChange", "speaker", "bluetooth"))
}
print("Speaker intent regression cases passed")
