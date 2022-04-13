//
//  ARSceneController+RecordAR.swift
//  XYARKit
//
//  Created by user on 4/8/22.
//

import UIKit
import ARKit
import SceneKit
import SCNRecorder
import Photos
import AVKit

public extension ARSceneController {
    func setupARRecord() {
        sceneView.prepareForRecording()
    }
    
    @objc
    func recordingAction(_ sender: UIButton) {
        if sender.tag == 100 {
            do {
//                let screen = UIScreen.main.bounds
//                let scale = UIScreen.main.scale
//                let width = screen.width * scale
//                let height = screen.height*scale
//                let size = CGSize(width: width, height: height)
                
                let videoRecording = try sceneView.startVideoRecording()
                
                videoRecording.$duration.observe(on: .main) { [weak self] duration in
                    self?.timeLabel.text = String(format: "%02d:%02d", Int(duration) / 60, Int(duration) % 60)
                }
            } catch {
                
            }
            sender.setTitle("Stop", for: .normal)
            sender.tag = 200
        } else {
            sceneView.finishVideoRecording { (videoRecording) in
                
                DispatchQueue.global().async {
                    let filePath = videoRecording.url.path
                    let videoCompatible = UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(filePath)
                    if videoCompatible {
                        UISaveVideoAtPathToSavedPhotosAlbum(filePath, self, #selector(self.didFinishSavingVideo(videoPath:error:contextInfo:)), nil)
                    } else {
                        print("该视频无法保存至相册")
                    }
                }
                
                /* Process the captured video. Main thread. */
                let controller = AVPlayerViewController()
                controller.player = AVPlayer(url: videoRecording.url)
                controller.modalPresentationStyle = .overFullScreen
                self.present(controller, animated: true)
            }
            sender.setTitle("Start", for: .normal)
            sender.tag = 100
        }
    }
    
    @objc
    func didFinishSavingVideo(videoPath: String, error: NSError?, contextInfo: UnsafeMutableRawPointer?) {
        if error != nil{
            print("保存失败")
        }else{
            print(videoPath)
            print("保存成功，请到相册中查看")
            self.timeLabel.text = "00:00"
        }
    }
}

