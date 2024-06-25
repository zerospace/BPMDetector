//
//  BPMDetector.swift
//  BPMDetector
//
//  Created by Oleksandr Fedko on 25.06.2024.
//

import Foundation
import Accelerate

struct BPM {
    struct Debug {
        let occurrence: [Float]
        let amplitude: [Float]
    }
    
    let value: Float
    let debug: Debug?
    
    init(_ value: Float) {
        self.value = value
        self.debug = nil
    }
    
    init(_ value: Float, debug: Debug) {
        self.value = value
        self.debug = debug
    }
}

struct BPMDetector {
    private let dwt = Wavelet()
    
    func compute(in data: [Float], sampleRate: Float) -> BPM {
        let halfSR = sampleRate / 2
        let levels = 4
        var cA = data
        var cD = [Float]()
        var loopCounter = 0
        var peakDiff2 = [Float](repeating: 0.0, count: Int(halfSR))
        var peakThold = [Float]()
        var peakWindow = [Float]()
        var peakDiff = [Float]()
        var deltaPickDiff = [Float]()
        while loopCounter < levels {
            let powLoop = pow(2.0, Float(loopCounter))
            loopCounter += 1
            
            let result = dwt.transform(cA, wavelet: .db2)
            cA = result.0
            cD = result.1
            
            // Full wave rectification
            vDSP_vabs(cD, 1, &cD, 1, vDSP_Length(cD.count))
            
            // Apply moving window for getting the peak position
            peakWindow = [Float]()
            var i = 1
            let thold = 20
            let windowSize = Int(round((sampleRate / 8) / powLoop))
            let windowMove = windowSize / thold
            var length = cD.count  - windowSize
            while i < length {
                let indexOfMaximum = vDSP.indexOfMaximum(cD[i..<i+windowSize])
                peakWindow.append(Float(i + Int(indexOfMaximum.0)))
                i += windowMove
            }
            
            // Calculate the IOI from the peak position
            var peakCount = (sample: [Float](), count: [Float]())
            peakCount.sample.append(peakWindow[0])
            peakCount.count.append(1)
            length = peakWindow.count
            var j = 0
            i = 1
            while i < length {
                if peakWindow[i] == peakCount.sample[j] {
                    peakCount.count[j] += 1
                }
                else {
                    j += 1
                    peakCount.sample.append(peakWindow[i])
                    peakCount.count.append(1)
                }
                i += 1
            }
            
            // Filter out any peaks which are not the maximum for 90% of the time
            peakThold = [Float]()
            length = peakCount.sample.count
            i = 0
            let maxThold = Float(thold) * 0.9
            while i < length {
                if Float(peakCount.count[i]) >= maxThold {
                    peakThold.append(peakCount.sample[i])
                }
                i += 1
            }
            
            // Beat interval estimation
            peakDiff = [Float](repeating: 0, count: peakThold.count - 1)
            peakThold.withUnsafeBufferPointer { pointer in
                vDSP_vsub(pointer.baseAddress!, 1, pointer.baseAddress!.advanced(by: 1), 1, &peakDiff, 1, vDSP_Length(peakThold.count - 1))
            }
            
            // Compute the weight of each IOI
            let delta = 4
            if peakDiff.count <= 4 {
                continue
            }
            deltaPickDiff = [Float](repeating: 0.0, count: peakDiff.count - delta)
            i = delta
            length = deltaPickDiff.count
            while i < length {
                deltaPickDiff[i] = 0
                
                // By using Equation 3 "y = 320.67 x-0.3388", we set the beat deviation
                let tempBpm = (halfSR * 60) / peakDiff[i]
                let ms = 320.67 * pow(tempBpm, -0.3388)
                var weight = ms * halfSR / 1000 // change ms to W
                weight /= powLoop
                
                for j in -delta...delta {
                    // To check whether two IOIs are similar
                    if abs(peakThold[i+j] - (peakThold[i] + Float(j) * peakDiff[i])) <= weight {
                        deltaPickDiff[i] += 1
                    }
                }
                i += 1
            }
            
            // Construct the histogram
            i = delta
            length = peakDiff.count - delta
            while i < length {
                let newPeakDiff = peakDiff[i] * powLoop
                if newPeakDiff > 0 && Int(newPeakDiff) < Int(halfSR) {
                    peakDiff2[Int(newPeakDiff)] += deltaPickDiff[i] / Float(2 * delta + 1)
                }
                i += 1
            }
        }
        
        // Smooth the histogram with a Gaussian function
        let gaussFilter = gaussianLowPassFilter(size: 2205, sigma: 360)
        var peakDiff3 = [Float](repeating: 0.0, count: peakDiff2.count + gaussFilter.count - 1)
        let xPadded = [Float](repeating: 0.0, count: gaussFilter.count - 1) + peakDiff2 + [Float](repeating: 0.0, count: gaussFilter.count - 1)
        vDSP_conv(xPadded, 1, gaussFilter, 1, &peakDiff3, 1, vDSP_Length(peakDiff3.count), vDSP_Length(gaussFilter.count))
        let peakDiff4 = Array(peakDiff3[1102..<(peakDiff2.count + 1102)])
        
        let maxPosHistogram = vDSP.indexOfMaximum(peakDiff4)
        let bpm = (halfSR * 60) / Float(maxPosHistogram.0)
        return BPM(bpm, debug: BPM.Debug(occurrence: peakDiff2, amplitude: peakDiff4))
    }
    
    func gaussianLowPassFilter(size: Int, sigma: Float) -> [Float] {
        var filter = [Float](repeating: 0.0, count: size)
        let center = Float(size - 1) / 2.0
        var i = 0
        while i < size {
            filter[i] = exp(-pow(Float(i) - center, 2) / (2 * pow(sigma, 2)))
            i += 1
        }
        
        var totalSum: Float = 0.0
        let length = vDSP_Length(filter.count)
        vDSP_sve(&filter, 1, &totalSum, length)
        var result = [Float](repeating: 0.0, count: size)
        vDSP_vsdiv(&filter, 1, &totalSum, &result, 1, length)
        
        return result
    }
    
    func dynamicRange(in data: [Float]) -> Float {
        let length = vDSP_Length(data.count)
        var samples = [Float](repeating: 0.0, count: data.count)
        vDSP_vmul(data, 1, data, 1, &samples, 1, length)
        let mean = vDSP.mean(samples)
        return sqrt(mean)
    }
}
