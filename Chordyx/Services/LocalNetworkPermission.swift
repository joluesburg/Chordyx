//
//  LocalNetworkPermission.swift
//  Chordyx
//

import Foundation
import Network

/// Triggers the Local Network privacy prompt and verifies Bonjour access before MPC starts.
enum LocalNetworkPermission {
    static func requestAccess(serviceType: String) async {
        await withCheckedContinuation { continuation in
            var finished = false
            let finish: () -> Void = {
                guard !finished else { return }
                finished = true
                continuation.resume()
            }

            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            let descriptor = NWBrowser.Descriptor.bonjour(type: "_\(serviceType)._tcp", domain: nil)
            let browser = NWBrowser(for: descriptor, using: parameters)

            browser.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    browser.cancel()
                    finish()
                default:
                    break
                }
            }

            browser.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.5) {
                browser.cancel()
                finish()
            }
        }
    }
}
