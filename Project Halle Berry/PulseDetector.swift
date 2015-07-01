//
//  PulseDetector.swift
//  Project Halle Berry
//
//  Created by Daniel Wilson on 6/30/15.
//  Copyright © 2015 Daniel G Wilson. All rights reserved.
//

import Foundation
import QuartzCore
//import vector
//import algorithm

let MAX_PERIODS_TO_STORE = 20
let AVERAGE_SIZE = 20
let INVALID_PULSE_PERIOD = -1

let MAX_PERIOD = 1.5
let MIN_PERIOD = 0.1
let INVALID_ENTRY = -100

class PulseDetector : NSObject {
    var upVals = [Float](count: AVERAGE_SIZE, repeatedValue: 0.0)
    var downVals = [Float](count: AVERAGE_SIZE, repeatedValue: 0.0)
    var upValIndex : Int!
    var downValIndex : Int!
    
    var periodStart : Float = Float(CACurrentMediaTime())
    var periods = [Double](count: MAX_PERIODS_TO_STORE, repeatedValue: 0.0)
    var periodTimes = [Double](count: MAX_PERIODS_TO_STORE, repeatedValue: 0.0)
    
    var periodIndex : Int!
    var started : Bool! = false
    var freq : Float!
    
    var wasDown : Bool = false
    
    override init() {
        super.init()
        reset()
    }
    
    func reset()
    {
        for var i = 0; i < MAX_PERIODS_TO_STORE; i++ {
            periods[i] = Double(INVALID_ENTRY)
        }
        
        for var i = 0; i < AVERAGE_SIZE; i++ {
            upVals[i] = Float(INVALID_ENTRY)
            downVals[i] = Float(INVALID_ENTRY)
        }
        
        freq = 0.5
        periodIndex = 0
        downValIndex = 0
        upValIndex = 0
    }
    
    func addNewValue(newVal : Float, atTime time : Double) -> Int {
        // Keep track of the number of values above and below zero
        if newVal > 0 {
            upVals[upValIndex!] = newVal
            upValIndex!++
            if upValIndex >= AVERAGE_SIZE {
                upValIndex = 0
            }
        } else if newVal < 0 {
            downVals[downValIndex!] = -newVal
            downValIndex!++
            if downValIndex >= AVERAGE_SIZE {
                downValIndex = 0
            }
        }
        
        // Get average above and below zero
        var count : Float = 0
        var total : Float = 0
        for var i = 0; i < AVERAGE_SIZE; i++ {
            if upVals[i] != Float(INVALID_ENTRY) {
                count++
                total += upVals[i]
            }
        }
        let averageUp = total / count
        
        // Average down
        count = 0
        total = 0
        for var i = 0; i < AVERAGE_SIZE; i++ {
            if downVals[i] != Float(INVALID_ENTRY) {
                count++
                total += downVals[i]
            }
        }
        let averageDown = total / count
        
        // is the new value a down value?
        if newVal < -0.5 * averageDown {
            wasDown = true
        }
        
        // is the new value an up value and were we previously in the down state?
        if newVal >= 0.5 * averageUp && wasDown
        {
            wasDown = false
            
            // Find the time difference between now and the last time this happened
            if time - Double(periodStart) < MAX_PERIOD && time - Double(periodStart) > MIN_PERIOD {
                periods[periodIndex!] = time - Double(periodStart)
                periodTimes[periodIndex!] = time
                periodIndex!++
                if periodIndex >= MAX_PERIODS_TO_STORE {
                    periodIndex = 0
                }
            }
            
            // Track when the transition occurred
            periodStart = Float(time)
        }
        
        // return up or down
        if newVal < -0.5 * averageDown {
            return -1
        } else if newVal > 0.5 * averageUp {
            return 1
        }
        return 0
    }
    
    func getAverage() -> Double {
        let time = CACurrentMediaTime()
        var total : Double = 0
        var count : Double = 0
        for var i = 0; i < MAX_PERIODS_TO_STORE; i++ {
            if periods[i] != Double(INVALID_ENTRY) && time - periodTimes[i] < 10 {
                count++
                total += periods[i]
            }
        }
        
        // Check to see if there are enough values
        if count > 2
        {
            return total / count
        }
        
        return Double(INVALID_PULSE_PERIOD)
    }
}