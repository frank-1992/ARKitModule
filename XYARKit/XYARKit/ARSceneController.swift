//
//  ARSceneController.swift
//  
//
//  Created by user on 4/6/22.
//

import UIKit
import SceneKit
import ARKit

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
    
    /// the latest screen touch position when a pan gesture is active
    private var lastPanTouchPosition: CGPoint?
    
    ///  about shadow
    private var shadowPlane: SCNNode?
    private var lightNode:SCNNode?
    
    private lazy var light: SCNLight = {
        let light = SCNLight()
        light.type = .directional
        light.shadowColor = UIColor.black.withAlphaComponent(0.5)
        light.shadowRadius = 5
        light.shadowSampleCount = 5
        light.castsShadow = true
        light.shadowCascadeCount = 3
        light.shadowCascadeSplittingFactor = 0.09
        light.shadowBias = 0.1
        light.categoryBitMask = -1
        light.shadowMode = .deferred
        return light
    }()
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        loadVirtualObject(with: "万得虎-firework")
        setupSceneView()
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
    }
    
    // MARK: - add light to scene
    private func addLight() {
        if lightNode != nil {
            lightNode?.removeFromParentNode()
            lightNode = nil
        }

        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.eulerAngles = SCNVector3(x: -.pi/3, y: 0, z: 0)
        sceneView.scene.rootNode.addChildNode(lightNode)
    }
    
    private func addShadowPlane(with loaction: CGPoint) {
        if shadowPlane != nil {
            shadowPlane?.removeFromParentNode()
            shadowPlane = nil
        }
        
        let floor = SCNFloor()
        floor.reflectivity = 0
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        
        // https://stackoverflow.com/questions/30975695/scenekit-is-it-possible-to-cast-an-shadow-on-an-transparent-object/44799498#44799498
        material.colorBufferWriteMask = SCNColorMask(rawValue: 0)
        floor.materials = [material]
        
        guard let newPlaneData = anyPlaneFrom(location: loaction) else { return }
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = newPlaneData.1
        sceneView.scene.rootNode.addChildNode(floorNode)
        shadowPlane = floorNode
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
        if let object = placedObject {
            if let hitTestResult = sceneView.smartHitTest(touchLocation) {
                object.simdPosition = hitTestResult.worldTransform.translation
            }
        } else {
            // add virtual object
            guard let virtualObject = loadedVirtualObject else {
                return
            }
            place(virtualObject, basedOn: touchLocation)
            placedObject = virtualObject
            virtualObject.shouldUpdateAnchor = true
            if virtualObject.shouldUpdateAnchor {
                virtualObject.shouldUpdateAnchor = false
                self.updateQueue.async {
                    self.sceneView.addOrUpdateAnchor(for: self.loadedVirtualObject!)
                }
            }
        }
        addShadowPlane(with: touchLocation)
    }
    
    // MARK: - 放置模型
    func place(_ object: SCNNode, basedOn location: CGPoint) {
        guard let hitTestResult = sceneView.smartHitTest(location)
            else { return }
        object.pivot = SCNMatrix4MakeTranslation(
            0,
            object.boundingBox.min.y+2,
            0
        )
        
        sceneView.scene.rootNode.addChildNode(object)
        object.scale = SCNVector3(0.01, 0.01, 0.01)
        object.simdWorldPosition =  hitTestResult.worldTransform.translation
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
                placedObject?.objectRotation += Float(translation.x/100)
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
        
//        let width = CGFloat(planeAnchor.extent.x)
//        let height = CGFloat(planeAnchor.extent.z)
//        let plane = SCNPlane(width: width, height: height)
//        plane.materials.first?.writesToDepthBuffer = true
//        plane.materials.first?.readsFromDepthBuffer = true
//        plane.firstMaterial?.lightingModel = .shadowOnly
//
//        let planeNode = SCNNode(geometry: plane)
//        let x = planeAnchor.center.x
//        let y = planeAnchor.center.y
//        let z = planeAnchor.center.z
//        planeNode.position = SCNVector3(x: x, y: y, z: z)
//        planeNode.eulerAngles.x = -.pi/2
//        planeNode.castsShadow = false
//        node.addChildNode(planeNode)
    }
    
    public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        // update plane
//        guard let planeNode = node.childNodes.first,
//              let plane = planeNode.geometry as? SCNPlane else {
//            return
//        }
//        let width = CGFloat(planeAnchor.extent.x)
//        let height = CGFloat(planeAnchor.extent.z)
//        plane.width = width
//        plane.height = height
//        let x = planeAnchor.center.x
//        let y = planeAnchor.center.y
//        let z = planeAnchor.center.z
//        planeNode.position = SCNVector3(x: x, y: y, z: z)
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