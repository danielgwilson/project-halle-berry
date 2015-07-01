//
//  HBViewController.swift
//  Project Halle Berry
//
//  Created by Daniel Wilson on 6/29/15.
//  Copyright (c) 2015 Daniel G Wilson. All rights reserved.
//

// Strongly referenced from SampleHeartRateApp created by chris of CMG Research Ltd.

import UIKit
import AVFoundation

let MIN_FRAMES_FOR_FILTER_TO_SETTLE = 10

enum CURRENT_STATE : UInt {
    case STATE_PAUSED
    case STATE_SAMPLING
}

class HBViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, BEMSimpleLineGraphDelegate, BEMSimpleLineGraphDataSource {
    
    var filter                  : Filter?
    var pulseDetector           : PulseDetector?
    
    var filteredPoints          : [CGFloat] = [CGFloat](count: 20, repeatedValue: 5.0)
    
    let session                 : AVCaptureSession = AVCaptureSession()
    var camera                  : AVCaptureDevice?
    var validFrameCounter       : Int = 0
    var currentState            : CURRENT_STATE?
    
    @IBOutlet var pulseRate     : UILabel?
    @IBOutlet var validFrames   : UILabel?
    @IBOutlet var graph         : BEMSimpleLineGraphView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        filter = Filter()
        pulseDetector = PulseDetector()
//        startCameraCapture()
        
        setUpGraph()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
//        resume()
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
//        pause()
    }
    
    // MARK: Capture Methods
    func startCameraCapture() {
        session.beginConfiguration()
        camera = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        
        // Turn on torch mode/flashlight
        if camera!.hasTorch {
            do {
                try camera!.lockForConfiguration()
                try camera!.setTorchModeOnWithLevel(1.0)
                camera!.unlockForConfiguration()
            } catch {
                print("camera initialization issue")
            }
        }
        
        // AVCaptureDeviceInput with device camera
        var videoInput : AVCaptureDeviceInput?
        do {
            try videoInput = AVCaptureDeviceInput(device: camera!)
        } catch {
            print("Error creating AVCapture")
        }
        
        // Output handling
        let videoOutput = AVCaptureVideoDataOutput()
        
        // Separate running queue for capture
        let captureQueue : dispatch_queue_t = dispatch_queue_create("captureQueue", nil)
        
        // Set self as capture delegate
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        
        // Pixel format configuration
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey : NSNumber(unsignedInt: kCVPixelFormatType_32BGRA)]
        
        // Minimum framerate
        do {
            try camera!.lockForConfiguration()
            camera!.activeVideoMinFrameDuration = CMTimeMake(1, 10)
            camera!.unlockForConfiguration()
        } catch {
            print("camera framerate initialization issue")
        }
        
        // Set frame size to smallest because only intensity matters
        session.sessionPreset = AVCaptureSessionPresetLow
        
        // Add input and output
        session.addInput(videoInput)
        session.addOutput(videoOutput)
        
        session.commitConfiguration()
        
//        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
//        self.view.layer.addSublayer(previewLayer)
//        previewLayer?.frame = self.view.layer.frame
        
        // Start session
        session.startRunning()
        
        // Started sampling
        currentState = .STATE_SAMPLING
        
        // Prevent app sleep
        UIApplication.sharedApplication().idleTimerDisabled = true
        
        NSTimer.scheduledTimerWithTimeInterval(0.1, target: self, selector: Selector("update"), userInfo: nil, repeats: true)
    }
    
    func stopCameraCapture() {
        session.stopRunning()
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        
        if currentState == .STATE_PAUSED
        {
            validFrameCounter = 0
            return
        }
        
        // Image buffer
        let cvimgRef : CVImageBufferRef = CMSampleBufferGetImageBuffer(sampleBuffer)!
        // Lock image buffer
        CVPixelBufferLockBaseAddress(cvimgRef, 0)
        
        // Access the data
        let width : size_t = CVPixelBufferGetWidth(cvimgRef)
        let height : size_t = CVPixelBufferGetHeight(cvimgRef)
        
        // Get raw image data
        var buf = UnsafeMutablePointer<UInt8>(CVPixelBufferGetBaseAddress(cvimgRef))
        
        let bprow : size_t = CVPixelBufferGetBytesPerRow(cvimgRef)
        
        // Grab AVERAGE RGB value of entire frame
        var r, g, b : Float
        r = 0
        g = 0
        b = 0
        for var y = 0; y < height; y++ {
            for var x = 0; x < width * 4; x+=4 {
                b += Float(buf[x])
                g += Float(buf[x + 1])
                r += Float(buf[x + 2])
            }
            buf += bprow
        }
        let totalValueRange = 255 * Float(width * height)
        r /= totalValueRange
        g /= totalValueRange
        b /= totalValueRange
        
        // Convert to HSV colorspace
        let hsv = rgbToHSV(r, g: g, b: b)
        
        // "Sanity Check" for finger actually on camera
        if hsv["s"] > 0.5 && hsv["v"] > 0.5 {
            // Valid frame here
            validFrameCounter++
            
            // Filter noise with simple band pass filter
            // Remove DC components and high frequency noise
            let filtered = filter!.processValue(hsv["h"]!)
            filteredPoints.removeAtIndex(0)
            filteredPoints.append(CGFloat(filtered))
//            print(filteredPoints)
            
            // Need enough frames for the filter to settle
            if validFrameCounter > MIN_FRAMES_FOR_FILTER_TO_SETTLE {
                // Add the new value to the pulse detector
                pulseDetector!.addNewValue(filtered, atTime: CACurrentMediaTime())
            }
        } else {
            validFrameCounter = 0
            // Clear the pulse detector
            // Only need to do this once before adding the first values
            pulseDetector!.reset()
        }
    }
    
    // MARK: Pause and Resume of Pulse Detection
    func pause() {
        if currentState != .STATE_PAUSED {
            return
        }
        
        // Turn off the torch while paused
        if camera!.hasTorch {
            do {
                try camera!.lockForConfiguration()
                camera!.torchMode = AVCaptureTorchMode.Off
                camera!.unlockForConfiguration()
            } catch {
                print("camera torch off issue")
            }
        }
        
        currentState = .STATE_PAUSED
        UIApplication.sharedApplication().idleTimerDisabled = false
    }
    
    func resume() {
        if currentState == .STATE_PAUSED
        {
            return
        }
        
        // Turn torch back on
        if camera!.hasTorch {
            do {
                try camera!.lockForConfiguration()
                try camera!.setTorchModeOnWithLevel(1.0)
                camera!.unlockForConfiguration()
            } catch {
                print("camera initialization issue")
            }
        }
        
        currentState = .STATE_SAMPLING
        UIApplication.sharedApplication().idleTimerDisabled = true
    }
    
    // MARK: Helper Methods
    // Convert RGB to CSV for intensity comparison
    func rgbToHSV(r : Float, g : Float, b : Float) -> [String : Float] {
        let minimum : Float = min( r, g, b )
        let maximum : Float = max( r, g, b )
        var hsv : [String : Float] = [ : ]
        hsv["v"] = maximum
        let delta : Float = maximum - minimum
        
        if maximum != 0 {
            hsv["s"] = delta / maximum
        } else {
            // r = g = b = 0
            hsv["s"] = 0
            hsv["h"] = -1
            return hsv
        }
        
        if r == maximum {
            hsv["h"] = ( g - b ) / delta
        } else if g == maximum {
            hsv["h"] = 2 + ( b - r ) / delta
        } else {
            hsv["h"] = 4 + ( r - g ) / delta
        }
        
        hsv["h"] = hsv["h"]! * 60
        
        if hsv["h"] < 0 {
            hsv["h"] = hsv["h"]! + 360
        }
        
        return hsv
    }
    
    // Update fields
    func update() {
        validFrames?.text = "Valid Frames: \(String(min(100, (100 * validFrameCounter) / MIN_FRAMES_FOR_FILTER_TO_SETTLE)))"
        
        if currentState == .STATE_PAUSED {
            // do nothing while paused
            return
        }
        
        let avePeriod : Double = pulseDetector!.getAverage()
        if avePeriod == Double(INVALID_PULSE_PERIOD) {
            // no pulse value available
            pulseRate?.text = "--"
        } else {
            let pulse = 60.0 / avePeriod
            pulseRate?.text = NSString(format: "%0.0f", pulse) as String
        }
        
        print(graph?.graphValuesForDataPoints())
    }
    
    // MARK: Graph Methods
    func setUpGraph() {
        // Extra setup not handled in storyboard
    }
    
    func numberOfPointsInLineGraph(graph: BEMSimpleLineGraphView) -> Int {
        return filteredPoints.count
    }
    
    func lineGraph(graph: BEMSimpleLineGraphView, valueForPointAtIndex index: Int) -> CGFloat {
        return filteredPoints[index]
    }
    
    func lineGraphDidFinishDrawing(graph: BEMSimpleLineGraphView) {
//        graph.reloadGraph()
    }
}