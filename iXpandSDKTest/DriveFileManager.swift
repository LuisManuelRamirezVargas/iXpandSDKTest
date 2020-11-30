//
//  DriveFileManager.swift
//  iXpandSDKTest
//
//  Created by LRamirezVargas on 18/11/20.
//

import Foundation
import ExternalAccessory

class DriveFileManager {
    
    static let FSC_LEN_MAXTRANFER = DWORD(48 * 1024)
    static let MAX_WRITE_BUFFER_SIZE = DWORD(FSC_LEN_MAXTRANFER * 10)
    static let MAX_APIDATA_SIZE = DWORD(MAX_WRITE_BUFFER_SIZE)
    static let MAX_DATABUFFER = DWORD(1024 * 480)
    
    let validSandiskIds = [
        "com.sandisk.ixpandflashdrive",
        "com.sandisk.ixpandv2",
        "com.sandisk.ixpandv3",
        "com.sandisk.ixpandv6",
        "com.sandisk.ixpandv7"
    ]
    
    var accessoryConnected = false
    var sessionClosed = true
    var printOnUICallback: (String) -> ()
    var byDataBuf = [UInt8](repeating:0, count:Int(DriveFileManager.MAX_APIDATA_SIZE))
    //let path = "/stations.shapefile"
    let path = "/stations.txt"
    
    init(printOnUICallback: @escaping (String) -> ()) {
        self.printOnUICallback = printOnUICallback
    }

    func openSession() -> String {
        let connectedAccessories = EAAccessoryManager.shared().connectedAccessories
        guard connectedAccessories.count > 0 else {
            printOnUI("Please connect an accessory!")
            return "Unknown"
        }
        guard let accessory = connectedAccessories.first else { return "Unknown" }
        printOnUI("accessory info")
        printOnUI("accessory.name = \(accessory.name)")
        printOnUI("accessory.connectionID = \(accessory.connectionID)")
        printOnUI("accessory.modelNumber = \(accessory.modelNumber)")
        printOnUI("accessory.modelNumber = \(accessory.protocolStrings)")
        
        if accessory.protocolStrings.contains(where: validSandiskIds.contains) {
            printOnUI("SanDisk accessory connected.")
            connect(accessory: accessory)
            return accessory.name
        } else {
            printOnUI("Please connect SanDisk accessory.")
            return "Unknown"
        }
    }
    
    func closeSession() -> String {
        if(!sessionClosed && accessoryConnected) {
            sessionClosed = true
            iXpandSystemController.shared()?.closeSession()
            printOnUI("Session Closed.")
            return "Session Closed, Thank you!"
        } else {
            return "Error! No connected accessory or No active session!"
        }
    }
    
    func connect(accessory: EAAccessory) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let semaphore = DispatchSemaphore(value: 0)
            
            var accStatus: AccessoryCallbacks? = nil
            iXpandSystemController.shared()?.checkAccessoryUseFlag({ (accessoryStatus) in
                accStatus = accessoryStatus
                semaphore.signal()
            })
            
            _ = semaphore.wait(timeout: .distantFuture)
            
            if let accStatus = accStatus,
               accStatus != ACCESSORY_FREE { 
                self.printOnUI("Accessory in use by some other app!")
            }
            
            if let status = iXpandSystemController.shared()?.initDrive(accessory),
               !status {
                self.printOnUI("Drive Initialisation failed")
            }
            self.printOnUI("Establish with \(accessory.protocolStrings)")
            
            let success = iXpandSystemController.shared()?.openSession()
            
            if let success = success, !success {
                self.printOnUI("Accessory not connected")
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.accessoryConnected = true
                self.sessionClosed = false
                self.printOnUI("Session established successfully!")
            }
        }
    }
    
    func writeFileToDrive() {
        guard !sessionClosed && accessoryConnected else {
            printOnUI("Error! No accessory or No active session!")
            return
        }
        var error: NSError? = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.writeDataToFileAtPath(self.path, error: &error)
        }
    }
    
    func readFileFromDrive() {
        guard !sessionClosed && accessoryConnected else {
            printOnUI("Error! No accessory or No active session!")
            return
        }
        printOnUI("Reading File, Please wait")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let path = self.path

            let handle = self.openFile(atPath: path, mode: BYTE(OF_READ))
            
            self.printOnUI("readFileFromDrive handle = \(handle)")
            
            if(handle == -1) {
                self.printOnUI("File is not available. Please write first!")
            } else {
                let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                                isDirectory: true)
                var isDir: ObjCBool = true
                let folderExist = FileManager.default.fileExists(atPath: temporaryDirectoryURL.relativePath, isDirectory: &isDir)
                if folderExist {
                    self.printOnUI("TemporaryDirectory exist")
                } else {
                    do {
                        try FileManager.default.createDirectory(atPath: temporaryDirectoryURL.relativePath, withIntermediateDirectories: true, attributes: nil)
                    } catch {
                        self.printOnUI("cannot create TemporaryDirectory \(error)")
                    }
                }
                let temporaryFilename = "fileToRead.txt"

                let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(temporaryFilename)

                var uintDataCount: DWORD = 0
                self.printOnUI("temporal path = \(temporaryFileURL.relativePath)")
                guard let fHandle = self.makeFileOpenPath(filePath: temporaryFileURL.relativePath) else {
                    self.printOnUI("cannot make File Open Path")
                    return
                }
                
                repeat {
                    let singleTransfer: Int = 480 * 1024;
                    var aData: NSData = NSMutableData(bytes: malloc(singleTransfer), length: singleTransfer)
                    if let dataCount = iXpandFileSystemController.shared()?.readFile(handle, readBuf: aData as Data, readSize: DWORD(singleTransfer)) {
                        uintDataCount = dataCount
                    } else {
                        break
                    }
                    if((uintDataCount != -1) && (uintDataCount != 0)) {
                        aData = NSData(bytes: aData.bytes, length: Int(uintDataCount))
                        self.makeFileHandle(fHandle, writeData: aData as Data)
                    }
                } while ((uintDataCount != -1) && (uintDataCount != 0))
                
                if(uintDataCount == 0) {
                    self.printOnUI("File read successful")
                    let fileContent = try? String(contentsOf: temporaryFileURL, encoding: .utf8)
                    self.printOnUI("File content: \(String(describing: fileContent))")
                    try? FileManager.default.removeItem(at: temporaryFileURL)
                } else {
                    self.printOnUI("File read failed")
                }
                
                fHandle.closeFile()
                iXpandFileSystemController.shared()?.closeFile(handle)
            }
        }
    }
    
    func makeFileHandle(_ fileHandle: FileHandle, writeData data: Data) {
        fileHandle.write(data)
    }
    
    func makeFileOpenPath(filePath: String) -> FileHandle? {
        if (FileManager.default.fileExists(atPath: filePath, isDirectory: nil)) {
            self.printOnUI("file exist: filePath = \(filePath)")
            return nil
        } else {
            let success = FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil)
            if success {
                printOnUI("file created")
            } else {
                printOnUI("cannot create file")
            }
        }
        guard let fileHandle = FileHandle.init(forUpdatingAtPath: filePath) else {
            self.printOnUI("cannot init filePath = \(filePath)")
            return nil
        }
        fileHandle.seek(toFileOffset: fileHandle.seekToEndOfFile())
        return fileHandle
    }
    
    func writeDataToFileAtPath(_ path: String, error: inout NSError?) {
        printOnUI("writing file: \(path)")
        
        var isDirectory: ObjCBool = false
        let itemExists = iXpandFileSystemController.shared()?
            .itemExists(path, isDirectory: &isDirectory)
        
        guard let exist = itemExists, !exist else {
            printOnUI("File already present, please delete!")
            return
        }
        
        printOnUI("Writing File, Please wait...")
        
        guard let stringPath = Bundle.main.path(forResource: "stations", ofType: "txt") else {
            printOnUI("Cannot find Path")
            return
        }
        printOnUI("stringPath = \(stringPath)")
        guard let fileHandle = FileHandle.init(forReadingAtPath: stringPath) else {
            printOnUI("Cannot init fileHandle")
            return
        }
        
        let handle = openFile(atPath: path, mode: BYTE(OF_CREATE | OF_WRITE))
        
        printOnUI("handle = \(handle)")
        
        if (handle == -1)
        {
            printOnUI("Cannot open file handle")
            return;
        }
        
        if (handle != -1) {
            var dataLength: DWORD = 0
            var uintDataSize: DWORD = 0
            var uintDataTranLen: DWORD = 0
            guard let fileSize = returnFileSize(filePath: stringPath) else { return }
            uintDataSize = UInt32(fileSize)
            printOnUI("File size \(uintDataSize)")
            let serialQueue = DispatchQueue(label: "com.iXpand.writefile")
            serialQueue.sync {
                while((dataLength != -1) && (uintDataSize != 0)) {
                    autoreleasepool {
                        uintDataTranLen = ((uintDataSize > Self.MAX_DATABUFFER) ? Self.MAX_DATABUFFER : uintDataSize)
                        let data = fileHandle.readData(ofLength: Int(uintDataTranLen))
                        data.copyBytes(to: &byDataBuf, count: Int(uintDataTranLen))
                        let aData = Data(byDataBuf)
                        dataLength = iXpandFileSystemController.shared()?.writeFile(handle, writeBuf: aData, writeSize: uintDataTranLen) ?? 0
                        uintDataSize -= dataLength
                    }
                }
                iXpandFileSystemController.shared()?.closeFile(handle)
                fileHandle.closeFile()
            }
        }
        printOnUI("File was written successfully!")
    }
    
    func openFile(atPath path: String, mode: BYTE) -> Int {
        var handle: Int = -1
        printOnUI("Opening File")
        iXpandFileSystemController.shared()?.changeDirectoryAbsolutePath("/")
        autoreleasepool {
            handle = iXpandFileSystemController.shared()?.openFileAbsolutePath(path, openMode: mode) ?? -1
        }
        return handle
    }
    
    func returnFileSize(filePath: String) -> UInt64? {
        let fileManager = FileManager.default
        var fileSize: UInt64? = nil
        if (fileManager.fileExists(atPath: filePath, isDirectory: nil)) {
            do {
                let attr = try fileManager.attributesOfItem(atPath: filePath)
                fileSize = attr[FileAttributeKey.size] as? UInt64
            } catch {
                print("Error: \(error)")
            }
        }
        return fileSize
    }
    
    func printOnUI(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.printOnUICallback(text)
        }
    }
}
