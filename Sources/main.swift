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


        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error  in
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
    func pair(){
         var pairoptions: [String:Any]      =   [
                    "Request": "Pair",
                    "PairingOptions": [                       
                    "PairingType": "Lockdown",
                    "SupportsWiFi": true,
                    "SupportsAppInstall": true,
                    "SupportsDebugging": true
                    ]
                ]
         let error = try? sendRequest(emulateMac(with: pairoptions))
        print(error)
    }
    
    func emulateMac(with additionalData: [String: Any]?) -> [String: Any] {
        var macData: [String: Any] = [
            "HostID": UUID().uuidString,        // This creates a unique ID for the host (I hope)
            "HostInfo": [
                "SystemName": "macOS",
                "SystemVersion": "15.0",             // You can modify this as needed
                "ComputerName": "MacBook Pro",         
                "ProtocolVersion": "2",              // If you see this please help, idk any documented vers past 2
    
            ]
        ]
        
        // Merge the additional data into the macData dictionary
        if let additionalData {
            for (key, value) in additionalData {
                macData[key] = value
            }
        }
        
        return macData
    
    }
    func startService(name: String, port: Int){
        var StartOpts: [String:Any] = [
            "Request":"StartService",
            "Port": port,
            "Service": name]
        let err = try? sendRequest(emulateMac(with: StartOpts))
        print(err)
    }
    func StartDebugServer(){
        startService(name: "com.apple.debugserver", port: 12345) // is this port ok?
    }
}

func ignoremeimexampleusage() {
    let LM = LockdowndMuxer()
    do {
        try LM.connectToLockdownd()
    } catch {
        print(error.localizedDescription)
    }

    let response = try? LM.sendRequest(LM.emulateMac(with: nil)) // I need to find out how to launch debug server... thank you libimobiledevice
    print(response)
}
