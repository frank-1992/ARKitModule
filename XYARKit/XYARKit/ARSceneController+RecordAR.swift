//
//  ARSceneController+RecordAR.swift
//  XYARKit
//
//  Created by user on 4/8/22.
//

import UIKit
import ARKit
import SceneKit
import ARVideoKit
import Photos

public extension ARSceneController {
    func setupARRecord() {
        recorder = RecordAR(ARSceneKit: sceneView)
        // Set the recorder's delegate
        recorder?.delegate = self

        // Set the renderer's delegate
        recorder?.renderAR = self
        
        // Configure the renderer to perform additional image & video processing 👁
        recorder?.onlyRenderWhileRecording = false
        
        // Configure ARKit content mode. Default is .auto
        recorder?.contentMode = .aspectFill
        
        //record or photo add environment light rendering, Default is false
        recorder?.enableAdjustEnvironmentLighting = true
        
        // Set the UIViewController orientations
//        recorder?.inputViewOrientations = [.landscapeLeft, .landscapeRight, .portrait]
        // Configure RecordAR to store media files in local app directory
        recorder?.deleteCacheWhenExported = false
    }
    
    @objc
    func recordingAction(_ sender: UIButton) {
        if recorder?.status == .recording {
            sender.setTitle("Start", for: .normal)
            recorder?.stop() { path in
                self.recorder?.export(video: path) { saved, status in
                    print("文件路径: \(path)")
                    DispatchQueue.main.sync {
                        self.exportMessage(success: saved, status: status)
                    }
                }
            }
        } else {
            sender.setTitle("Stop", for: .normal)
            recordingQueue.async {
                self.recorder?.record()
            }
        }
    }
    
    
    // MARK: - Exported UIAlert present method
    func exportMessage(success: Bool, status:PHAuthorizationStatus) {
        if success {
            let alert = UIAlertController(title: "Exported", message: "Media exported to camera roll successfully!", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Awesome", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }else if status == .denied || status == .restricted || status == .notDetermined {
            let errorView = UIAlertController(title: "😅", message: "Please allow access to the photo library in order to save this media file.", preferredStyle: .alert)
            let settingsBtn = UIAlertAction(title: "Open Settings", style: .cancel) { (_) -> Void in
                guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                if UIApplication.shared.canOpenURL(settingsUrl) {
                    if #available(iOS 10.0, *) {
                        UIApplication.shared.open(settingsUrl, completionHandler: { (success) in
                        })
                    } else {
                        UIApplication.shared.openURL(URL(string:UIApplication.openSettingsURLString)!)
                    }
                }
            }
            errorView.addAction(UIAlertAction(title: "Later", style: UIAlertAction.Style.default, handler: {
                (UIAlertAction)in
            }))
            errorView.addAction(settingsBtn)
            self.present(errorView, animated: true, completion: nil)
        }else{
            let alert = UIAlertController(title: "Exporting Failed", message: "There was an error while exporting your media file.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }

}

// MARK: - RecordARDelegate
extension ARSceneController: RecordARDelegate {
    public func recorder(didEndRecording path: URL, with noError: Bool) {
        
    }
    
    public func recorder(didFailRecording error: Error?, and status: String) {
        
    }
    
    public func recorder(willEnterBackground status: RecordARStatus) {
        if status == .recording {
            recorder?.stopAndExport()
        }
    }
}

// MARK: - RenderARDelegate
extension ARSceneController: RenderARDelegate {
    public func frame(didRender buffer: CVPixelBuffer, with time: CMTime, using rawBuffer: CVPixelBuffer) {
        // Do some image/video processing.
    }
}
