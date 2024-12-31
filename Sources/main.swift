import Foundation
import Network

class LockdowndMuxer {
    private var connection: NWConnection?

    init() {

        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 62078) // usbmuxd port
        self.connection = NWConnection(to: endpoint, using: .tcp)
    }

    func connectToLockdownd() throws {
        guard let connection = self.connection else {
            throw NSError(domain: "LockdowndMuxer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize connection"])
        }

        let semaphore = DispatchSemaphore(value: 0)
        var connectionError: Error?

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Connected to usbmuxd.")
                semaphore.signal()
            case .failed(let error):
                connectionError = error
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: .main)
        semaphore.wait()

        if let error = connectionError {
            throw error
        }
    }

    func sendRequest(_ request: [String: Any]) throws -> [String: Any] {
        guard let connection = self.connection else {
            throw NSError(domain: "LockdowndMuxer", code: 2, userInfo: [NSLocalizedDescriptionKey: "No active connection"])
        }


        let requestData = try PropertyListSerialization.data(fromPropertyList: request, format: .binary, options: 0)

        let semaphore = DispatchSemaphore(value: 0)
        var responseError: Error?
        var responseData: Data?

        connection.send(content: requestData, completion: .contentProcessed { error in
            if let error = error {
                responseError = error
            }
            semaphore.signal()
        })
        semaphore.wait()

        if let error = responseError {
            throw error
        }


        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, error in
            if let data = data {
                responseData = data
            }
            if let error = error {
                responseError = error
            }
            semaphore.signal() // sempahore basically restricts access to resources by 0 (locked), 1 (unlocked), or more meaning the no. of threads allowed to access
            // sempahore.wait() -1
            // sempahore.signal() +1
        }
        semaphore.wait()

        if let error = responseError {
            throw error
        }

        guard let data = responseData else {
            throw NSError(domain: "LockdowndMuxer", code: 3, userInfo: [NSLocalizedDescriptionKey: "No response received"])
        }

        guard let response = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw NSError(domain: "LockdowndMuxer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        return response
    }
    func emulateMac() -> [String: Any] {
        return [
            "Request": "Pair",
            "HostID": UUID().uuidString,        // idk if this method actually exists, I hope so
            "HostInfo": [
                "SystemName": "macOS",
                "SystemVersion": "15.0",             // would this be fine?
                "ComputerName": "MacBook Pro",         
                "ProtocolVersion": "2" // only up till procotol version 2 is documented
                "PairingOptions": [                       
                    "PairingType": "Lockdown",
                    "SupportsWiFi": true,
                    "SupportsAppInstall": true,
                    "SupportsDebugging": true
                ]
            ],

}

func ignoremeimexampleusage(){
  let LM = LockdowndMuxer()
  LM.connectToLockdownd()

  let response = try LM.sendRequest(emulateMac()) // I need to find out how to launch debug server...
}
