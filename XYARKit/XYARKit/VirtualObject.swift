//
//  VirtualObject.swift
//  XYARKit
//
//  Created by user on 4/6/22.
//

import UIKit
import SceneKit
import ARKit


public enum ObjectAlignment: Int {
    case horizontal = 0
    case vertical = 1
    case face = 2
    case air = 3
    case all = 4
}

@available(iOS 13.0, *)
public final class VirtualObject: SCNReferenceNode {

    /// object name
    public var modelName: String {
        return referenceURL.lastPathComponent.replacingOccurrences(of: ".usdz", with: "")
    }
    
    /// alignments - 'horizontal, vertical, any'
    public var allowedAlignment: ARRaycastQuery.TargetAlignment {
        return .any
    }
    
    public var currentPlaneAlignment: ObjectAlignment? {
        didSet {
            switch currentPlaneAlignment {
            case .horizontal:
                /// choose which light and shadow
                horizontalLightNode?.isHidden = false
                verticalLightNode?.isHidden = true
                /// change modle's pivot
                setupHorizontalPivot()
                setupHorizontalShadows()
                /// choose which shadowplane
                horizontalShadowPlaneNode?.isHidden = false
                verticalShadowPlaneNode?.isHidden = true
            case .vertical:
                /// choose which light and shadow
                horizontalLightNode?.isHidden = true
                verticalLightNode?.isHidden = false
                /// change modle's pivot
                setupVerticalPivot()
                setupVerticalShadows()
                /// choose which shadowplane
                verticalShadowPlaneNode?.isHidden = false
                horizontalShadowPlaneNode?.isHidden = true
            default:
                break
            }
        }
    }
    
    /// object's  ARAnchor
    public var anchor: ARAnchor?
    
    /// raycastQuery info when place object
    public var raycastQuery: ARRaycastQuery?
    
    /// the associated tracked raycast used to place this object.
    public var raycast: ARTrackedRaycast?
    
    /// the most recent raycast result used for determining the initial location of the object after placement
    public var mostRecentInitialPlacementResult: ARRaycastResult?
    
    /// if associated anchor should be updated at the end of a pan gesture or when the object is repositioned
    public var shouldUpdateAnchor = false
    
    /// ????????????????????????????????????
    public func stopTrackedRaycast() {
        raycast?.stopTracking()
        raycast = nil
    }
    
    private var horizontalShadowPlaneNode: SCNNode?
    private var verticalShadowPlaneNode: SCNNode?
    private var horizontalLightNode: SCNNode?
    private var verticalLightNode: SCNNode?
    
    public init?(resourceName: String) {
        guard let modelURL = Bundle.main.url(forResource: resourceName, withExtension: "usdz", subdirectory: "Models.scnassets") else {
            fatalError("can't find virtual object")
        }
        super.init(url: modelURL)
        self.load()
        self.name = resourceName
        addHorizontalLight()
        addVerticalLight()
        setupHorizontalPivot()
        setupHorizontalShadows()
    }
    
    public override init?(url referenceURL: URL) {
        super.init(url: referenceURL)
        self.load()
        addHorizontalLight()
        addVerticalLight()
        setupHorizontalPivot()
        setupHorizontalShadows()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    // MARK: - setup pivot
    public func setupHorizontalPivot() {
        self.pivot = SCNMatrix4MakeTranslation(
            0,
            self.boundingBox.min.y,
            0
        )
    }
    
    public func setupVerticalPivot() {
        let x = self.boundingBox.min.x + (self.boundingBox.max.x - self.boundingBox.min.x) / 2
        let y = self.boundingBox.min.y + (self.boundingBox.max.y - self.boundingBox.min.y) / 2
        let z = self.boundingBox.min.z
        
        self.pivot = SCNMatrix4MakeTranslation(
            x,
            y,
            z
        )
    }
    
    // MARK: - horizontal shadow settings
    private func setupHorizontalShadows() {
        guard horizontalShadowPlaneNode == nil else { return }
        let width: CGFloat = CGFloat(self.boundingBox.max.x - self.boundingBox.min.x)
        let length: CGFloat = CGFloat(self.boundingBox.max.z - self.boundingBox.min.z)
        
        let plane = SCNPlane(width: width, height: length)
        plane.firstMaterial?.diffuse.contents = UIColor.red
        plane.firstMaterial?.lightingModel = .shadowOnly
        
        let planeNode = SCNNode(geometry: plane)
        let x = self.boundingBox.min.x + (self.boundingBox.max.x - self.boundingBox.min.x) / 2
        let y = self.boundingBox.min.y
        let z = self.boundingBox.min.z + (self.boundingBox.max.z - self.boundingBox.min.z) / 2
        planeNode.position = SCNVector3(x: x,
                                        y: y,
                                        z: z)
        planeNode.eulerAngles.x = -.pi / 2
        self.addChildNode(planeNode)
        horizontalShadowPlaneNode = planeNode
    }
    
    // MARK: - vertical shadow settings
    private func setupVerticalShadows() {
        guard verticalShadowPlaneNode == nil else { return }
        let height = CGFloat(self.boundingBox.max.y - self.boundingBox.min.y)
        let width = CGFloat(self.boundingBox.max.x - self.boundingBox.min.x)
        
        let plane = SCNPlane(width: width, height: height)
        plane.firstMaterial?.diffuse.contents = UIColor.red
        plane.firstMaterial?.lightingModel = .shadowOnly

        
        let planeNode = SCNNode(geometry: plane)
        let x = self.boundingBox.min.x + (self.boundingBox.max.x - self.boundingBox.min.x) / 2
        let y = self.boundingBox.min.y + (self.boundingBox.max.y - self.boundingBox.min.y) / 2
        let z = self.boundingBox.min.z
        planeNode.position = SCNVector3(x: x,
                                        y: y,
                                        z: z)
        self.addChildNode(planeNode)
        verticalShadowPlaneNode = planeNode
    }
    
    // MARK: - add horizontal light to cast shadow
    private func addHorizontalLight() {
        let light = SCNLight()
        light.type = .directional
        light.shadowColor = UIColor.black.withAlphaComponent(0.3)
        light.shadowRadius = 5
        light.shadowSampleCount = 5
        light.castsShadow = true
        light.shadowMode = .forward

        let shadowLightNode = SCNNode()
        shadowLightNode.light = light
        /// horizontal
        shadowLightNode.eulerAngles = SCNVector3(x: -.pi / (2 + FixValue.lightNodeAngleFix), y: 0, z: 0)
        self.addChildNode(shadowLightNode)
        horizontalLightNode = shadowLightNode
    }
    
    // MARK: - add vertical light to cast shadow
    private func addVerticalLight() {
        let light = SCNLight()
        light.intensity = 300
        light.type = .directional
        light.shadowColor = UIColor.black.withAlphaComponent(0.3)
        light.shadowRadius = 5
        light.shadowSampleCount = 5
        light.castsShadow = true
        light.shadowMode = .forward

        let shadowLightNode = SCNNode()
        shadowLightNode.isHidden = true
        shadowLightNode.light = light
        /// horizontal
        shadowLightNode.eulerAngles = SCNVector3(x: 0, y: -FixValue.lightNodeAngleFix, z: 0)
        self.addChildNode(shadowLightNode)
        verticalLightNode = shadowLightNode
    }
}

// MARK: - VirtualObject extensions
@available(iOS 13.0, *)
public extension VirtualObject {
    /// return existing virtual node
    static func existingObjectContainingNode(_ node: SCNNode) -> VirtualObject? {
        if let virtualObjectRoot = node as? VirtualObject {
            return virtualObjectRoot
        }
        
        guard let parent = node.parent else { return nil }
        
        return existingObjectContainingNode(parent)
    }
    
    static func minOne<T: Comparable>( _ seq: [T]) -> T {
        assert(!seq.isEmpty)
        return seq.reduce(seq[0]) {
            min($0, $1)
        }
    }
    
    static func maxOne<T: Comparable>( _ seq: [T]) -> T {
        assert(!seq.isEmpty)
        return seq.reduce(seq[0]) {
            max($0, $1)
        }
    }
}
