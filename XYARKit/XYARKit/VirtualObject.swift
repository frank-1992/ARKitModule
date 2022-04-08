//
//  VirtualObject.swift
//  XYARKit
//
//  Created by user on 4/6/22.
//

import UIKit
import SceneKit
import ARKit

public final class VirtualObject: SCNReferenceNode {

    /// object name
    public var modelName: String {
        return referenceURL.lastPathComponent.replacingOccurrences(of: ".usdz", with: "")
    }
    
    /// alignments - 'horizontal, vertical, any'
    public var allowedAlignment: ARRaycastQuery.TargetAlignment {
        return .any
    }
    
    /// object's rotation
    public var objectRotation: Float {
        get {
            return childNodes.first!.eulerAngles.y
        }
        set (newValue) {
            childNodes.first!.eulerAngles.y = newValue
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
    
    /// 停止跟踪模型的位置和方向
    public func stopTrackedRaycast() {
        raycast?.stopTracking()
        raycast = nil
    }
    
    public init(resourceName: String) {
        guard let modelURL = Bundle.main.url(forResource: resourceName, withExtension: "usdz", subdirectory: "Models.scnassets") else {
            fatalError("can't find virtual object")
        }
        super.init(url: modelURL)!
        self.load()
        
        setupPivot()
        setupShadows()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    // MARK: - setup pivot
    private func setupPivot(){
        self.pivot = SCNMatrix4MakeTranslation(
            0,
            self.boundingBox.min.y,
            0
        )
    }
    
    // MARK: - shadow settings
    private func setupShadows() {        
        let value1: CGFloat = CGFloat(self.boundingBox.max.x - self.boundingBox.min.x)
        let value2: CGFloat = CGFloat(self.boundingBox.max.z - self.boundingBox.min.z)
        let value3: CGFloat = CGFloat(self.boundingBox.max.z - self.boundingBox.min.x)
        let value4: CGFloat = CGFloat(self.boundingBox.max.x - self.boundingBox.min.z)
        
        let min = minOne([value1, value2, value3, value4])
        let edge = sqrt(min*min*2)
        let plane = SCNPlane(width: edge, height: edge)
        plane.firstMaterial?.diffuse.contents = UIColor.red
        plane.firstMaterial?.lightingModel = .shadowOnly
        
        let planeNode = SCNNode(geometry: plane)
        let x = self.boundingBox.min.x + (self.boundingBox.max.x - self.boundingBox.min.x)/2
        let y = self.boundingBox.min.y
        let z = self.boundingBox.min.z + (self.boundingBox.max.z - self.boundingBox.min.z)/2
        planeNode.position = SCNVector3(x: x,
                                        y: y,
                                        z: z)
        planeNode.eulerAngles.x = -.pi/2
        self.addChildNode(planeNode)
    }
}

// MARK: - VirtualObject extensions
public extension VirtualObject {
    /// return existing virtual node
    static func existingObjectContainingNode(_ node: SCNNode) -> VirtualObject? {
        if let virtualObjectRoot = node as? VirtualObject {
            return virtualObjectRoot
        }
        
        guard let parent = node.parent else { return nil }
        
        return existingObjectContainingNode(parent)
    }
    
    func minOne<T:Comparable>( _ seq:[T]) -> T{
        assert(seq.count>0)
        return seq.reduce(seq[0]){
            min($0, $1)
        }
    }
}
