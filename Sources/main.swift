import Foundation
import Network
import Security

class LockdowndMuxer {
    private var connection: NWConnection?
    private var puK: SecKey
    private var prK: SecKey
    private var B64C: String
    private var B64K: String

    init() {

        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 62078) // usbmuxd port
        self.connection = NWConnection(to: endpoint, using: .tcp)
        let (PK, PK2) = generateB64Keepair()
        puK = PK!
        prK = PK2!
        B64C = Data(SecKeyToPEM(puK,"PUBLIC")!).base64EncodedString()
        B64K = Data(SecKeyToPEM(puK,"PRIVATE")!).base64EncodedString()
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
         sendRequest(emulateMac(with: pairoptions))
          
    }
    func emulateMac(with additionalData: [String: Any]) -> [String: Any] {
        var macData: [String: Any] = [
            "HostID": UUID().uuidString,        // This creates a unique ID for the host (I hope)
            "HostInfo": [
                "SystemName": "macOS",
                "SystemVersion": "15.0",             // You can modify this as needed
                "ComputerName": "MacBook Pro",         
                "ProtocolVersion": "2",              // If you see this please help, idk any documented vers past 2
    
            ]
            "HostCertificate": B64C,
            "HostPrivateKey": B64K
        ]
        
        // Merge the additional data into the macData dictionary
        for (key, value) in additionalData {
            macData[key] = value
        }
        
        return macData
    
    }
    func startService(name: String, port: Int){
        var StartOpts: [String:Any] = [
            "Request":"StartService",
            "Port": port,
            "Service": name]
        sendRequest(emulateMac(StartOpts))
    }
    func StartDebugServer(){
        startService(name: "com.apple.debugserver", port: 12345) // is this port ok?
    }
    // bad joke
    func generateB64Keepair() -> (publicKey: SecKey?,privateKey: SecKey?) {
    let keyPairAttr: [String:Any] = [
    "kSecAttrKeyType": kSecAttrKeyTypeRSA, // is this changable?
    "kSecAttrKeySizeInBits": 2048,
    "kSecPrivateKeyAttrs": [
    "kSecAttrIsPermanent": false // no keychain
    ],
    "kSecPublicKeyAttrs": [
    "kSecAttrIsPermanent": false // no to u 2
    ]
    ]
    var publicKey, privateKey: SecKey?

    let stat = SecKeyGeneratePair(keyPairAttr as CFDictionary, &publicKey, &privateKey)
    if status == errSecSuccess {
        return (publicKey,privateKey)
    } else {
    print("Unable to generate key values")
    return (nil,nil)
    }

    }
    func SecKeyToPEM(pubK: SecKey,type:String) -> String? {
    var error: Unmanaged<CFError>?
    guard let pubK = SecKeyCopyExternalRepresentation(pubK,&error) else {
    print("Error: \(error!.takeRetainedValue())")
    return nil
    }
    let b64E = (pubK as Data).base64EncodedString(options: [])
    let PEM = "-----BEGIN \(type) KEY-----\n" + b64E + "\n-----END \(type) KEY-----"
    }
    return PEM

}

func ignoremeimexampleusage(){
  let LM = LockdowndMuxer()
  LM.connectToLockdownd()

  let response = try LM.sendRequest(emulateMac()) // I need to find out how to launch debug server... thank you libimobiledevice
    
}
