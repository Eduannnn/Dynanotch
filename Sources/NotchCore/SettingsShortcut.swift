public func isNotchSettingsShortcut(characters: String?, command: Bool, shift: Bool, option: Bool, control: Bool, overNotch: Bool) -> Bool {
    overNotch && characters == "," && command && !shift && !option && !control
}
