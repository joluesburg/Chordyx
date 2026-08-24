//
//  PhoneOrientationMonitor.swift
//  Chordyx
//
//  Detects physical iPhone landscape via accelerometer + UIDevice so Piano Keys
//  can rotate even when Control Center orientation lock keeps the UI in portrait.
//

import Combine
import Foundation
#if canImport(UIKit)
import CoreMotion
import UIKit
#endif

#if os(iOS)
@MainActor
final class PhoneOrientationMonitor: ObservableObject {
    static let shared = PhoneOrientationMonitor()

    @Published private(set) var isLandscape = false
    @Published private(set) var landscapeRotationDegrees: Double = 90

    private let motion = CMMotionManager()
    private var started = false
    private var orientationObserver: NSObjectProtocol?

    func start() {
        guard !started else { return }
        started = true

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PhoneOrientationMonitor.shared.applyUIDeviceOrientation()
            }
        }
        applyUIDeviceOrientation()

        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.12
        motion.startAccelerometerUpdates(to: .main) { data, _ in
            guard let acceleration = data?.acceleration else { return }
            let ax = acceleration.x
            let ay = acceleration.y
            Task { @MainActor in
                PhoneOrientationMonitor.shared.applyAcceleration(ax: ax, ay: ay)
            }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
    }

    private func applyUIDeviceOrientation() {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            // Device rotated left; counter-rotate content so it reads upright.
            setLandscape(true, degrees: -90)
        case .landscapeRight:
            setLandscape(true, degrees: 90)
        case .portrait, .portraitUpsideDown:
            setLandscape(false, degrees: landscapeRotationDegrees)
        default:
            break
        }
    }

    /// Gravity-based detection — works while UIDevice reports .faceUp / .unknown.
    private func applyAcceleration(ax: Double, ay: Double) {
        // Landscape when sideways tilt dominates.
        if abs(ax) > 0.5, abs(ax) > abs(ay) + 0.05 {
            // Match UIDevice: ax > 0 ≈ landscapeLeft → -90° content rotation.
            setLandscape(true, degrees: ax > 0 ? -90 : 90)
        } else if abs(ay) > 0.5, abs(ay) > abs(ax) + 0.05 {
            setLandscape(false, degrees: landscapeRotationDegrees)
        }
    }

    private func setLandscape(_ landscape: Bool, degrees: Double) {
        if isLandscape != landscape {
            isLandscape = landscape
        }
        if landscape, landscapeRotationDegrees != degrees {
            landscapeRotationDegrees = degrees
        }
    }
}

final class ChordyxAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Do not start CoreMotion / MainActor services here — that raced the splash
        // and could freeze launch on device. ContentView starts them after home is ready.
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .allButUpsideDown
    }
}
#endif
