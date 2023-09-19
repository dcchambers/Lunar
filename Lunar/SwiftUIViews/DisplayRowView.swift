import Defaults
import SwiftUI

struct DisplayRowView: View {
    static var hoveringVolumeSliderTask: DispatchWorkItem? {
        didSet {
            oldValue?.cancel()
        }
    }

    @ObservedObject var display: Display
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.colors) var colors
    @Default(.showSliderValues) var showSliderValues
    #if arch(arm64)
        @Default(.syncNits) var syncNits
    #endif

    @Default(.showInputInQuickActions) var showInputInQuickActions
    @Default(.showPowerInQuickActions) var showPowerInQuickActions
    @Default(.showXDRSelector) var showXDRSelector
    @Default(.showRawValues) var showRawValues
    @Default(.xdrTipShown) var xdrTipShown
    @Default(.autoXdr) var autoXdr
    @Default(.syncMode) var syncMode

    @State var showNeedsLunarPro = false
    @State var showXDRTip = false
    @State var showSubzero = false
    @State var showXDR = false

    @State var hoveringVolumeSlider = false

    @Default(.autoBlackoutBuiltin) var autoBlackoutBuiltin

    @State var adaptiveStateText = ""
    @State var adaptivePausedText = "Adaptive brightness paused"

    @State var editingMaxNits = false
    @State var editingMinNits = false

    @State var hovering = false

    var softwareSliders: some View {
        Group {
            if display.enhanced {
                BigSurSlider(
                    percentage: $display.xdrBrightness,
                    image: "sun.max.circle.fill",
                    color: Colors.xdr.opacity(0.7),
                    backgroundColor: Colors.xdr.opacity(colorScheme == .dark ? 0.1 : 0.2),
                    knobColor: Colors.xdr,
                    showValue: $showSliderValues,
                    beforeSettingPercentage: { _ in display.forceHideSoftwareOSD = true }
                )
            }
            if display.subzero {
                BigSurSlider(
                    percentage: $display.softwareBrightness,
                    image: "moon.circle.fill",
                    color: Colors.subzero.opacity(0.7),
                    backgroundColor: Colors.subzero.opacity(colorScheme == .dark ? 0.1 : 0.2),
                    knobColor: Colors.subzero,
                    showValue: $showSliderValues,
                    beforeSettingPercentage: { _ in display.forceHideSoftwareOSD = true }
                ) { _ in
                    guard display.adaptiveSubzero else { return }

                    let lastDataPoint = datapointLock.around { DC.adaptiveMode.brightnessDataPoint.last }
                    display.insertBrightnessUserDataPoint(lastDataPoint, display.brightness.doubleValue, modeKey: DC.adaptiveModeKey)
                }
            }
        }
    }

    var sdrXdrSelector: some View {
        HStack(spacing: 2) {
            SwiftUI.Button("SDR") {
                guard display.enhanced else { return }
                withAnimation(.fastSpring) { display.enhanced = false }
            }
            .buttonStyle(PickerButton(
                onColor: Color.black, offColor: .oneway { colors.invertedGray }, enumValue: $display.enhanced, onValue: false
            ))
            .font(.system(size: 11, weight: display.enhanced ? .semibold : .bold, design: .monospaced))

            SwiftUI.Button("XDR") {
                guard lunarProActive || lunarProOnTrial else {
                    showNeedsLunarPro = true
                    return
                }
                guard !display.enhanced else { return }
                withAnimation(.fastSpring) { display.enhanced = true }
                if !xdrTipShown, autoXdr {
                    xdrTipShown = true
                    mainAsyncAfter(ms: 2000) {
                        showXDRTip = true
                    }
                }
            }
            .buttonStyle(PickerButton(
                onColor: Color.black, offColor: .oneway { colors.invertedGray }, enumValue: $display.enhanced, onValue: true
            ))
            .font(.system(size: 11, weight: display.enhanced ? .bold : .semibold, design: .monospaced))
            .popover(isPresented: $showNeedsLunarPro) { NeedsLunarProView() }
            .popover(isPresented: $showXDRTip) { XDRTipView() }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(colors.invertedGray))
        .padding(.bottom, 4)
    }

    var inputSelector: some View {
        Dropdown(
            selection: $display.inputSource,
            width: 150,
            height: 20,
            noValueText: "Video Input",
            noValueImage: "input",
            content: display.vendor == .lg ? .constant(VideoInputSource.mostUsed + [VideoInputSource.separator] + VideoInputSource.lgSpecific) : .constant(VideoInputSource.mostUsed)
        )
        .frame(width: 150, height: 20, alignment: .center)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(
                cornerRadius: 8,
                style: .continuous
            ).fill(Color.primary.opacity(0.15))
        )
        .colorMultiply(colors.accent.blended(withFraction: 0.7, of: .white))
    }

    var rotationSelector: some View {
        HStack {
            rotationPicker(0).help("No rotation")
            rotationPicker(90).help("90 degree rotation (vertical)")
            rotationPicker(180).help("180 degree rotation (upside down)")
            rotationPicker(270).help("270 degree rotation (vertical)")
        }
    }

    var disabledReason: String? {
        if display.noControls {
            return "No controls available"
        } else if display.useOverlay {
            if display.isInHardwareMirrorSet {
                return "Overlay dimming disabled while mirroring"
            } else if display.isIndependentDummy {
                return "Overlay dimming disabled for dummy"
            }
        }

        return nil
    }

    @ViewBuilder var appPresetAdaptivePaused: some View {
        if (display.hasDDC && showInputInQuickActions)
            || display.showOrientation
            || display.appPreset != nil
            || display.adaptivePaused
            || showRawValues && (display.lastRawBrightness != nil || display.lastRawContrast != nil || display.lastRawVolume != nil)
            || SWIFTUI_PREVIEW
        {
            VStack {
                if (display.hasDDC && showInputInQuickActions) || SWIFTUI_PREVIEW { inputSelector }
                if display.showOrientation || SWIFTUI_PREVIEW { rotationSelector }
                if let app = display.appPreset {
                    SwiftUI.Button("App Preset: \(app.name)") {
                        app.runningApps?.first?.activate()
                    }
                    .buttonStyle(FlatButton(color: .primary.opacity(0.1), textColor: .secondary.opacity(0.8)))
                    .font(.system(size: 9, weight: .semibold))
                }
                if display.adaptivePaused || SWIFTUI_PREVIEW {
                    SwiftUI.Button(adaptivePausedText) { display.adaptivePaused.toggle() }
                        .buttonStyle(FlatButton(color: .primary.opacity(0.1), textColor: .secondary.opacity(0.8)))
                        .font(.system(size: 9, weight: .semibold))
                        .onHover { hovering in
                            adaptivePausedText = hovering ? "Resume adaptive brightness" : "Adaptive brightness paused"
                        }
                }

                if showRawValues {
                    RawValuesView(display: display).frame(width: 220).padding(.vertical, 3)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                ).fill(Color.primary.opacity(0.05))
            )
            .padding(.vertical, 3)
        }
    }

    @ViewBuilder var volumeSlider: some View {
        if display.hasDDC, display.showVolumeSlider, display.ddcEnabled || display.networkEnabled {
            ZStack {
                BigSurSlider(
                    percentage: $display.preciseVolume.f,
                    imageBinding: .oneway { display.audioMuted ? "speaker.slash.fill" : "speaker.2.fill" },
                    colorBinding: .constant(colors.accent),
                    backgroundColorBinding: .constant(colors.accent.opacity(colorScheme == .dark ? 0.1 : 0.4)),
                    showValue: $showSliderValues,
                    disabled: $display.audioMuted,
                    enableText: "Unmute"
                )
                if hoveringVolumeSlider, !display.audioMuted {
                    SwiftUI.Button("Mute") {
                        display.audioMuted = true
                    }
                    .buttonStyle(FlatButton(
                        color: Colors.red.opacity(0.7),
                        textColor: .white,
                        horizontalPadding: 6,
                        verticalPadding: 2
                    ))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .transition(.scale.animation(.fastSpring))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(x: -120, y: 0)
                }
            }.onHover { hovering in
                Self.hoveringVolumeSliderTask = mainAsyncAfter(ms: 150) {
                    hoveringVolumeSlider = hovering
                }
            }
        }
    }

    @ViewBuilder var sliders: some View {
        if display.noDDCOrMergedBrightnessContrast {
            let mergedLockBinding = Binding<Bool>(
                get: { display.lockedBrightness && display.lockedContrast },
                set: { display.lockedBrightness = $0 }
            )
            HStack {
                #if arch(arm64)
                    NitsTextField(nits: $display.minNits, placeholder: "min", display: display)
                        .opacity(hovering ? 1 : 0)
                #endif
                BigSurSlider(
                    percentage: $display.preciseBrightnessContrast.f,
                    image: "sun.max.fill",
                    colorBinding: .constant(colors.accent),
                    backgroundColorBinding: .constant(colors.accent.opacity(colorScheme == .dark ? 0.1 : 0.4)),
                    showValue: $showSliderValues,
                    disabled: mergedLockBinding,
                    enableText: "Unlock",
                    insideText: nitsText
                )
                #if arch(arm64)
                    let maxNitsBinding = Binding<Double>(
                        get: { display.userMaxNits ?? display.maxNits },
                        set: {
                            display.userMaxNits = nil
                            display.maxNits = $0
                        }
                    )
                    NitsTextField(nits: maxNitsBinding, placeholder: "max", display: display)
                        .opacity(hovering ? 1 : 0)
                #endif
            }
            softwareSliders
        } else {
            BigSurSlider(
                percentage: $display.preciseBrightness.f,
                image: "sun.max.fill",
                colorBinding: .constant(colors.accent),
                backgroundColorBinding: .constant(colors.accent.opacity(colorScheme == .dark ? 0.1 : 0.4)),
                showValue: $showSliderValues,
                disabled: $display.lockedBrightness,
                enableText: "Unlock",
                insideText: nitsText
            )
            softwareSliders
            let contrastBinding: Binding<Float> = Binding(
                get: { display.preciseContrast.f },
                set: { val in
                    display.withoutLockedContrast {
                        display.preciseContrast = val.d
                    }
                }
            )
            BigSurSlider(
                percentage: contrastBinding,
                image: "circle.righthalf.fill",
                colorBinding: .constant(colors.accent),
                backgroundColorBinding: .constant(colors.accent.opacity(colorScheme == .dark ? 0.1 : 0.4)),
                showValue: $showSliderValues
            )
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            let xdrSelectorShown = display.supportsEnhance && showXDRSelector && !display.blackOutEnabled
            if showPowerInQuickActions, display.getPowerOffEnabled() {
                HStack(alignment: .top, spacing: -10) {
                    Text(display.name)
                        .font(.system(size: 22, weight: .black))
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(colors.bg.primary.opacity(0.5)))
                        .padding(.bottom, xdrSelectorShown ? 0 : 6)

                    PowerOffButtonView(display: display)
                        .offset(y: -8)
                }.offset(x: 45)

            } else {
                Text(display.name ?! "Unknown")
                    .font(.system(size: 22, weight: .black))
                    .padding(.bottom, xdrSelectorShown ? 0 : 6)
            }

            if let disabledReason {
                Text(disabledReason).font(.system(size: 10, weight: .semibold, design: .rounded))
            } else if display.blackOutEnabled {
                Text("Blacked Out").font(.system(size: 10, weight: .semibold, design: .rounded))

                if display.isMacBook {
                    let binding = Binding<Bool>(
                        get: { autoBlackoutBuiltin },
                        set: {
                            autoBlackoutBuiltin = $0
                            display.keepDisconnected = $0
                        }
                    )

                    VStack {
                        SettingsToggle(
                            text: "Auto BlackOut",
                            setting: binding,
                            color: nil,
                            help: """
                            Turns off the built-in screen automatically when a monitor is connected and turns
                            it back on when the last monitor is disconnected.

                            Keeps the screen disconnected between standby/wake or lid open/close states.

                            Note: Press ⌘ Command more than 8 times in a row to force connect all displays.
                            """
                        )
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                    .padding(.vertical, 3)
                }
            } else {
                if xdrSelectorShown { sdrXdrSelector }

                sliders
                adaptiveState
                volumeSlider
                appPresetAdaptivePaused
            }
        }.onHover { h in withAnimation { hovering = h } }
    }

    @ViewBuilder var adaptiveState: some View {
        let systemAdaptive = display.systemAdaptiveBrightness
        let key = DC.adaptiveModeKey
        if !display.adaptive, !display.xdr, !display.blackout, !display.facelight, !display.subzero, (key == .sync && !display.isActiveSyncSource) || key == .location || key == .sensor || key == .clock {
            SwiftUI.Button(adaptiveStateText.isEmpty ? (systemAdaptive ? "Adapted by the system" : "Adaptive brightness disabled") : adaptiveStateText) {
                display.adaptive = true
            }
            .buttonStyle(FlatButton(color: .primary.opacity(0.1), textColor: .secondary.opacity(0.8)))
            .font(.system(size: 9, weight: .semibold))
            .onHover { hovering in
                adaptiveStateText = hovering ? "Adapt brightness with Lunar" : ""
            }
        }
    }

    func nitsText() -> AnyView {
        #if arch(arm64)
            guard SyncMode.isUsingNits(), display.isNative, let nits = display.nits else {
                return EmptyView().any
            }
            return VStack(spacing: -3) {
                Text("\(nits.intround)")
                Text("nits")
            }
            .font(.system(size: 8, weight: .bold, design: .rounded).leading(.tight))
            .foregroundColor((display.preciseBrightnessContrast < 0.25 && colorScheme == .dark) ? Colors.lightGray.opacity(0.6) : Colors.grayMauve.opacity(0.7))
            .any
        #else
            EmptyView().any
        #endif
    }

    func rotationPicker(_ degrees: Int) -> some View {
        SwiftUI.Button("\(degrees)°") {
            display.rotation = degrees
        }
        .buttonStyle(PickerButton(enumValue: $display.rotation, onValue: degrees))
        .font(.system(size: 12, weight: display.rotation == degrees ? .bold : .semibold, design: .monospaced))
        .help("No rotation")
    }
}