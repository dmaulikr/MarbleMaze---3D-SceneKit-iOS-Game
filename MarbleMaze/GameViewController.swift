//
//  GameViewController.swift
//  MarbleMaze
//
//  Created by Benjamin Pust on 12/18/16.
//  Copyright © 2016 Ben Pust. All rights reserved.
//

import UIKit
import SceneKit

class GameViewController: UIViewController {
    
    let CollisionCategoryBall = 1
    let CollisionCategoryStone = 2
    let CollisionCategoryPillar = 4
    let CollisionCategoryCrate = 8
    let CollisionCategoryPearl = 16
    
    var scnView: SCNView!
    var scnScene: SCNScene!
    
    var ballNode: SCNNode!
    var cameraNode: SCNNode!
    var cameraFollowNode:SCNNode!
    var lightFollowNode:SCNNode!
    
    var game = GameHelper.sharedInstance
    var motion = CoreMotionHelper()
    var motionForce = SCNVector3(0,0,0)
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupScene();
        setupNodes();
        setupSounds();
        resetGame()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if game.state == GameStateType.TapToPlay {
            playGame()
        }
    }

    func setupScene() {
        scnView = self.view as! SCNView
        scnView.delegate = self
//        scnView.allowsCameraControl = true
//        scnView.showsStatistics = true
        
        // scene
        scnScene = SCNScene(named: "art.scnassets/game.scn")
        scnView.scene = scnScene
        
        scnScene.physicsWorld.contactDelegate = self
    }

    func setupSounds() {
        game.loadSound(name: "GameOver", fileNamed: "GameOver.wav")
        game.loadSound(name: "Powerup", fileNamed: "Powerup.wav")
        game.loadSound(name: "Reset", fileNamed: "Reset.wav")
        game.loadSound(name: "Bump", fileNamed: "Bump.wav")
    }
    
    func setupNodes() {
        ballNode = scnScene.rootNode.childNode(withName: "ball", recursively: true)!
        ballNode.physicsBody!.contactTestBitMask = CollisionCategoryPillar | CollisionCategoryCrate | CollisionCategoryPearl
        
        cameraNode = scnScene.rootNode.childNode(withName: "camera", recursively: true)!
        let constraint = SCNLookAtConstraint(target: ballNode)
        constraint.isGimbalLockEnabled = true
        cameraNode.constraints = [constraint]
        
        cameraFollowNode = scnScene.rootNode.childNode(withName: "follow_camera",recursively: true)!
        cameraNode.addChildNode(game.hudNode)
        lightFollowNode = scnScene.rootNode.childNode(withName: "follow_light", recursively: true)!
    }
    
    override var shouldAutorotate: Bool {
        return false
    }
    override var prefersStatusBarHidden: Bool {
        return false
    }
    
    // MARK: GAME STATE
    
    func playGame() {
        game.state = GameStateType.Playing
        cameraFollowNode.eulerAngles.y = 0
        cameraFollowNode.position = SCNVector3Zero
        replenishLife()
    }

    func resetGame() {
        game.state = GameStateType.TapToPlay
        game.playSound(node: ballNode, name: "Reset")
        ballNode.physicsBody!.velocity = SCNVector3Zero
        ballNode.position = SCNVector3(x:0, y:10, z:0)
        cameraFollowNode.position = ballNode.position
        lightFollowNode.position = ballNode.position
        scnView.isPlaying = true
        game.reset()
    }

    func testForGameOver() {
        if ballNode.presentation.position.y < -5 {
            game.state = GameStateType.GameOver
            game.playSound(node: ballNode, name: "GameOver")
            ballNode.runAction(SCNAction.waitForDurationThenRunBlock(duration: 5) { (node:SCNNode!) -> Void in
                self.resetGame()
            })
        }
    }
    
    // MARK: UPDATE
    
    func updateMotionControl() {
        if game.state == GameStateType.Playing {
            motion.getAccelerometerData(interval: 0.1) { (x,y,z) in
                self.motionForce = SCNVector3(x: Float(x) * 0.05, y:0, z: Float(y+0.8) * -0.05)
            }
            ballNode.physicsBody!.velocity += motionForce
        }
    }
    
    /*  Update the cameraFollow position to match that of the ball as it rolls around  */
    func updateCameraAndLights() {
        
        /*
            Instead of simply setting the camera FollowNode position to that of ballNode,
            you calcualate a linearly-interpolated position to slowly move the camera 
            in the direction of ball. This creates a spectacular lazy camera effect.
        */
        let lerpX = (ballNode.presentation.position.x - cameraFollowNode.position.x) * 0.01
        let lerpY = (ballNode.presentation.position.y - cameraFollowNode.position.y) * 0.01
        let lerpZ = (ballNode.presentation.position.z - cameraFollowNode.position.z) * 0.01
        cameraFollowNode.position.x += lerpX
        cameraFollowNode.position.y += lerpY
        cameraFollowNode.position.z += lerpZ

        // Light is always in the same position as the cameraFollowNode
        lightFollowNode.position = cameraFollowNode.position

        
        /* Spins the camera in the right direction around the ball
           "cinamatic effect in the menu game state"    */
        if game.state == GameStateType.TapToPlay {
            cameraFollowNode.eulerAngles.y -= 0.005
        }
    }
    
    func updateHUD() {
        switch game.state {
        case .Playing:
            game.updateHUD()
        case .GameOver:
            game.updateHUD(s: "-GAME OVER-")
        case .TapToPlay:
            game.updateHUD(s: "-TAP TO PLAY-")
        }
    }
    
    // MARK: HEALTH
    
    func replenishLife() {
        let material = ballNode.geometry!.firstMaterial!
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.0
        material.emission.intensity = 1.0
        SCNTransaction.commit()
        game.score += 1
        game.playSound(node: ballNode, name: "Powerup")
    }
    func diminishLife() {
        let material = ballNode.geometry!.firstMaterial!
        if material.emission.intensity > 0 {
            material.emission.intensity -= 0.001
        } else {
            resetGame()
        }
    }
}

extension GameViewController: SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        updateMotionControl()
        updateCameraAndLights()
        updateHUD()
        
        if game.state == GameStateType.Playing {
            testForGameOver()
            diminishLife()
        }
    }
}

// MARK: PHYSICS
extension GameViewController : SCNPhysicsContactDelegate {
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        
        var contactNode:SCNNode!
        
        if contact.nodeA.name == "ball" {
            contactNode = contact.nodeB
        } else {
            contactNode = contact.nodeA
        }
        
        if contactNode.physicsBody!.categoryBitMask == CollisionCategoryPearl
        {
            contactNode.isHidden = true
            contactNode.runAction(SCNAction.waitForDurationThenRunBlock(duration: 30)
            { (node:SCNNode!) -> Void in
                node.isHidden = false
            })
            
            replenishLife()
        }
        if contactNode.physicsBody!.categoryBitMask == CollisionCategoryPillar
        {
            game.playSound(node: ballNode, name: "Bump")
        }
        
    }
}
