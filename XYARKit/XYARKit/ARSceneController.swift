//
//  ARSceneController.swift
//  
//
//  Created by user on 4/6/22.
//

import UIKit
import SceneKit
import ARKit
import SCNRecorder
import AVKit

public struct FixValue {
    // set loaded object's scale
    static let originObjectScale: Float = 0.01
    // solve the problem of plane flickering, the tilt angle is required
    static let lightNodeAngleFix: Float = 0.01
    // single pan gesture rotation sensitivity
    static let objectRotationFix: CGFloat = 100.0
    // correction of initial display model position relative to camera position Y
    static let cameraTranslationYFix: Float = 1.0
    // correction of initial display model position relative to camera position Z
    static let cameraTranslationZFix: Float = 2.0
}

public final class ARSceneController: UIViewController {

    public lazy var sceneView: ARView = {
        let sceneView = ARView(frame: view.bounds)
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        return sceneView
    }()
    
    public lazy var session: ARSession = {
        return sceneView.session
    }()
    
    let coachingOverlay = ARCoachingOverlayView()
    
    private let updateQueue = DispatchQueue(label: "armodule.serialSceneKitQueue")
    
    /// about virtual object
    private var loadedVirtualObject: VirtualObject?
    private var placedObject: VirtualObject?
    
    /// the flag about place object
    private var canPlaceObject: Bool = false
    
    private var placedObjectOnPlane: Bool = false
    
    /// the latest screen touch position when a pan gesture is active
    private var lastPanTouchPosition: CGPoint?
    
    private lazy var startRecordButton: UIButton = {
        let button = UIButton()
        button.setTitle("Start", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.systemBlue
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        button.layer.cornerRadius = 40
        button.tag = 100
        button.addTarget(self, action: #selector(recordingAction(_:)), for: .touchUpInside)
        return button
    }()
    
    public lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.textColor = UIColor.white
        label.font = UIFont.systemFont(ofSize: 16)
        label.textAlignment = .center
        label.text = "00:00"
        return label
    }()
    
    private lazy var light: SCNLight = {
        let light = SCNLight()
        light.type = .directional
        return light
    }()
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        loadVirtualObject(with: "万得虎-firework")
        setupSceneView()
//        displayVirtualObject()
        setupCoachingOverlay()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetTracking()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.isLightEstimationEnabled = true
        if #available(iOS 12.0, *) {
            configuration.environmentTexturing = .automatic
        }
       
        // add people occlusion
        // WARNING: - CPU High
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) else {
            fatalError("People occlusion is not supported on this device.")
        }
        switch configuration.frameSemantics {
        case [.personSegmentationWithDepth]:
            configuration.frameSemantics.remove(.personSegmentationWithDepth)
        default:
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - loadVirtualObject
    private func loadVirtualObject(with sourceName: String) {
        let virtualObject = VirtualObject(resourceName: sourceName)
        self.loadedVirtualObject = virtualObject
        print("模型加载成功")
        addGestures()
    }
    
    // MARK: - setup ARSceneView
    private func setupSceneView() {
        view.addSubview(sceneView)
        
        // light for scene
        addLight()
        
        // tap to place object
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(showVirtualObject(_:)))
        sceneView.addGestureRecognizer(tapGesture)
        
        // add record buttons
        view.addSubview(startRecordButton)
        startRecordButton.snp.makeConstraints { make in
            make.centerX.equalTo(view)
            make.bottom.equalTo(view).offset(-50)
            make.size.equalTo(CGSize(width: 80, height: 80))
        }
        
        // about video record
        setupARRecord()
        
        // show record time
        showRecordTime()
    }
    
    // MARK: - record time
    func showRecordTime() {
        view.addSubview(timeLabel)
        timeLabel.snp.makeConstraints { make in
            make.bottom.equalTo(startRecordButton.snp.top).offset(-6)
            make.centerX.equalTo(startRecordButton)
            make.width.equalTo(60)
            make.height.equalTo(30)
        }
    }
    
    // MARK: - display virtual object
    private func displayVirtualObject() {
        guard let virtualObject = loadedVirtualObject else {
            return
        }
        sceneView.scene.rootNode.addChildNode(virtualObject)
        virtualObject.scale = SCNVector3(FixValue.originObjectScale, FixValue.originObjectScale, FixValue.originObjectScale)
        virtualObject.simdWorldPosition = simd_float3(x: 0, y: 0, z: 0)
        placedObject = virtualObject
    }
    
    
    // MARK: - add light to scene
    private func addLight() {
        let light = SCNLight()
        light.type = .directional
        light.shadowColor = UIColor.black.withAlphaComponent(0.2)
        light.shadowRadius = 5
        light.shadowSampleCount = 5
        light.castsShadow = true
        light.shadowMode = .forward

        let shadowLightNode = SCNNode()
        shadowLightNode.light = light
        /// - Tag: 此处取值为2的话会出现plane闪烁的问题,需要灯光有一定的斜角
        shadowLightNode.eulerAngles = SCNVector3(x: -.pi/(2 + FixValue.lightNodeAngleFix), y: 0, z: 0)
        sceneView.scene.rootNode.addChildNode(shadowLightNode)
    }
    
    private func anyPlaneFrom(location: CGPoint) -> (SCNNode, SCNVector3)? {
        let results = sceneView.hitTest(location,
                                        types: ARHitTestResult.ResultType.existingPlaneUsingExtent)
        
        guard results.count > 0,
              let anchor = results[0].anchor,
              let node = sceneView.node(for: anchor) else { return nil }
        
        return (node, SCNVector3.positionFromTransform(results[0].worldTransform))
    }
    
    @objc
    private func showVirtualObject(_ gesture: UITapGestureRecognizer) {
        guard canPlaceObject else { return }
        let touchLocation = gesture.location(in: sceneView)
        guard let hitTestResult = sceneView.smartHitTest(touchLocation) else { return }

        if let object = placedObject {
            object.simdPosition = hitTestResult.worldTransform.translation
        } else {
            // add virtual object
            guard let virtualObject = loadedVirtualObject else {
                return
            }
            print(virtualObject)
            sceneView.scene.rootNode.addChildNode(virtualObject)
            virtualObject.scale = SCNVector3(FixValue.originObjectScale, FixValue.originObjectScale, FixValue.originObjectScale)
            virtualObject.simdWorldPosition =  hitTestResult.worldTransform.translation
            placedObject = virtualObject
            
//            virtualObject.shouldUpdateAnchor = true
//            if virtualObject.shouldUpdateAnchor {
//                virtualObject.shouldUpdateAnchor = false
//                self.updateQueue.async {
//                    self.sceneView.addOrUpdateAnchor(for: self.loadedVirtualObject!)
//                }
//            }
        }
    }
    
    // MARK: - add gestures
    private func addGestures() {
        // pan and rotate
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
        panGesture.delegate = self
        sceneView.addGestureRecognizer(panGesture)
        
        // scale
        let scaleGesture = UIPinchGestureRecognizer(target: self, action: #selector(didScale(_:)))
        scaleGesture.delegate = self
        sceneView.addGestureRecognizer(scaleGesture)
    }
    
    @objc
    func didPan(_ gesture: UIPanGestureRecognizer) {
        guard placedObject != nil else { return }
        switch gesture.state {
        case .changed:
            if let object = objectInteracting(with: gesture, in: sceneView) {

                let translation = gesture.translation(in: sceneView)
                let previousPosition = lastPanTouchPosition ?? CGPoint(sceneView.projectPoint(object.position))
                // calculate the new touch position
                let currentPosition = CGPoint(x: previousPosition.x + translation.x, y: previousPosition.y + translation.y)
                if let hitTestResult = sceneView.smartHitTest(currentPosition) {
                    object.simdPosition = hitTestResult.worldTransform.translation
                }
                lastPanTouchPosition = currentPosition
                // reset the gesture's translation
                gesture.setTranslation(.zero, in: sceneView)
            } else {
                // rotate
                let translation = gesture.translation(in: sceneView)
                placedObject?.objectRotation += Float(translation.x/FixValue.objectRotationFix)
                gesture.setTranslation(.zero, in: sceneView)
            }
        default:
            // clear the current position tracking.
            lastPanTouchPosition = nil
        }
    }
    
    @objc
    func didScale(_ gesture: UIPinchGestureRecognizer) {
        guard let object = placedObject, gesture.state == .changed
            else { return }
        let newScale = object.simdScale * Float(gesture.scale)
        object.simdScale = newScale
        gesture.scale = 1.0
    }
    
    private func objectInteracting(with gesture: UIGestureRecognizer, in view: ARSCNView) -> VirtualObject? {
        for index in 0..<gesture.numberOfTouches {
            let touchLocation = gesture.location(ofTouch: index, in: view)
            
            if let object = sceneView.virtualObject(at: touchLocation) {
                return object
            }
        }
        
        if let center = gesture.center(in: view) {
            return sceneView.virtualObject(at: center)
        }
        return nil
    }
}

// MARK: - ARSCNViewDelegate
extension ARSceneController: ARSCNViewDelegate {
    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        
    }
    
    public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // add plane
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        if planeAnchor.alignment == .horizontal {
            canPlaceObject = true
        }
        
//        DispatchQueue.global().async {
//            guard let placeObject = self.placedObject, self.placedObjectOnPlane == false else { return }
//            let touchLocation = self.sceneView.screenCenter
//            guard let hitTestResult = self.sceneView.smartHitTest(touchLocation) else { return }
//            placeObject.simdWorldPosition = hitTestResult.worldTransform.translation
//            self.placedObjectOnPlane = true
//        }
    }
    
    public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    }
}

// MARK: - ARSessionDelegate
extension ARSceneController: ARSessionDelegate {
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .limited(.initializing):
            print("初始化")
        case .limited(.excessiveMotion):
            print("过度移动")
        case .limited(.insufficientFeatures):
            print("缺少特征点")
        case .limited(.relocalizing):
            print("再次本地化")
        case .limited(_):
            print("未知原因")
        case .notAvailable:
            print("Tracking不可用")
        case .normal:
            print("正常")
    
        }
    }
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // load then show the model right away
//        let transform = frame.camera.transform
//        guard let placeObject = self.placedObject, self.placedObjectOnPlane == false else { return }
//        placeObject.simdWorldPosition = simd_float3(x: transform.translation.x, y: transform.translation.y - FixValue.cameraTranslationYFix, z: -FixValue.cameraTranslationZFix)
    }
    
    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        
    }
    
    public func session(_ session: ARSession, didFailWithError error: Error) {
        
    }
    
    public func sessionWasInterrupted(_ session: ARSession) {
        // Hide content before going into the background.
        
    }
    
    public func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return true
    }
    
}

// MARK: - UIGestureRecognizerDelegate
extension ARSceneController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // allow objects to be translated and rotated at the same time
        return true
    }
}
