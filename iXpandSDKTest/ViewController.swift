//
//  ViewController.swift
//  iXpandSDKTest
//
//  Created by LRamirezVargas on 18/11/20.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var responseLabel: UILabel!
    @IBOutlet weak var outputText: UITextView!
    var outputPipe:Pipe!
    
    var driveFileManager: DriveFileManager!

    override func viewDidLoad() {
        super.viewDidLoad()
        let printOnUICallback: (String) -> () = { text in
            let previousOutput = self.outputText.text ?? ""
            let nextOutput = previousOutput + text + "\n"
            self.outputText.text = nextOutput

            let range = NSRange(location:nextOutput.count,length:0)
            self.outputText.scrollRangeToVisible(range)
        }
        driveFileManager = DriveFileManager(printOnUICallback: printOnUICallback)
        // Do any additional setup after loading the view.
    }

    @IBAction func getDevices(_ sender: Any) {
        responseLabel.text = driveFileManager.openSession()
    }

    @IBAction func closeSession(_ sender: Any) {
        responseLabel.text = driveFileManager.closeSession()
    }
    
    @IBAction func readFile(_ sender: Any) {
        driveFileManager.readFileFromDrive()
    }

    @IBAction func writeFile(_ sender: Any) {
        driveFileManager.writeFileToDrive()
    }

    @IBAction func readFolder(_ sender: Any) {
    }
 
    func captureStandardOutputAndRouteToTextView() {
        outputPipe = Pipe()
        
        dup2(outputPipe.fileHandleForWriting.fileDescriptor, FileHandle.standardOutput.fileDescriptor)
        
        outputPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSFileHandleDataAvailable,
            object: outputPipe.fileHandleForReading, queue: nil) { notification in
            
            let output = self.outputPipe.fileHandleForReading.availableData
            let outputString = String(data: output, encoding: String.Encoding.utf8) ?? ""
            
            DispatchQueue.main.async(execute: {
                let previousOutput = self.outputText.text ?? ""
                let nextOutput = previousOutput + outputString
                self.outputText.text = nextOutput

                let range = NSRange(location:nextOutput.count,length:0)
                self.outputText.scrollRangeToVisible(range)
              })
            self.outputPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
        }
    }
}

