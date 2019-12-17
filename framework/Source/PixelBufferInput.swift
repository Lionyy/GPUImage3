//
//  PixelBufferInput.swift
//  GPUImage_iOS
//
//  Created by RoyLei on 12/17/19.
//  Copyright © 2019 Red Queen Coder, LLC. All rights reserved.
//

import AVFoundation

class PixelBufferInput: ImageSource {
    public let targets = TargetContainer()
        public var runBenchmark = false
        
        var videoTextureCache: CVMetalTextureCache?
        let yuvConversionRenderPipelineState:MTLRenderPipelineState
        var yuvLookupTable:[String:(Int, MTLDataType)] = [:]

        var numberOfFramesCaptured = 0
        var totalFrameTimeDuringCapture:Double = 0.0

        public init() {
            let (pipelineState, lookupTable) = generateRenderPipelineState(device:sharedMetalRenderingDevice, vertexFunctionName:"twoInputVertex", fragmentFunctionName:"yuvConversionFullRangeFragment", operationName:"YUVToRGB")
            self.yuvConversionRenderPipelineState = pipelineState
            self.yuvLookupTable = lookupTable
            let _ = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, sharedMetalRenderingDevice.device, nil, &videoTextureCache)
            
        }
        
        public func process(movieFrame frame:CMSampleBuffer) {
            let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(frame)
            let movieFrame = CMSampleBufferGetImageBuffer(frame)!
        
    //        processingFrameTime = currentSampleTime
            self.process(movieFrame:movieFrame, withSampleTime:currentSampleTime)
            CMSampleBufferInvalidate(frame)
        }
        
        public func process(movieFrame:CVPixelBuffer, withSampleTime:CMTime) {
            let bufferHeight = CVPixelBufferGetHeight(movieFrame)
            let bufferWidth = CVPixelBufferGetWidth(movieFrame)
            CVPixelBufferLockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))

            let conversionMatrix = colorConversionMatrix601FullRangeDefault
            // TODO: Get this color query working
    //        if let colorAttachments = CVBufferGetAttachment(movieFrame, kCVImageBufferYCbCrMatrixKey, nil) {
    //            if(CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == .EqualTo) {
    //                _preferredConversion = kColorConversion601FullRange
    //            } else {
    //                _preferredConversion = kColorConversion709
    //            }
    //        } else {
    //            _preferredConversion = kColorConversion601FullRange
    //        }
            
            let startTime = CFAbsoluteTimeGetCurrent()

            let texture:Texture?
            var luminanceTextureRef:CVMetalTexture? = nil
            var chrominanceTextureRef:CVMetalTexture? = nil
            // Luminance plane
            let _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, self.videoTextureCache!, movieFrame, nil, .r8Unorm, bufferWidth, bufferHeight, 0, &luminanceTextureRef)
            // Chrominance plane
            let _ = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, self.videoTextureCache!, movieFrame, nil, .rg8Unorm, bufferWidth / 2, bufferHeight / 2, 1, &chrominanceTextureRef)
            
            if let concreteLuminanceTextureRef = luminanceTextureRef, let concreteChrominanceTextureRef = chrominanceTextureRef,
                let luminanceTexture = CVMetalTextureGetTexture(concreteLuminanceTextureRef), let chrominanceTexture = CVMetalTextureGetTexture(concreteChrominanceTextureRef) {
                let outputTexture = Texture(device:sharedMetalRenderingDevice.device, orientation:.portrait, width:bufferWidth, height:bufferHeight, timingStyle:.videoFrame(timestamp:Timestamp(withSampleTime)))
                
                convertYUVToRGB(pipelineState:self.yuvConversionRenderPipelineState, lookupTable:self.yuvLookupTable,
                                luminanceTexture:Texture(orientation:.portrait, texture:luminanceTexture),
                                chrominanceTexture:Texture(orientation:.portrait, texture:chrominanceTexture),
                                resultTexture:outputTexture, colorConversionMatrix:conversionMatrix)
                texture = outputTexture
            } else {
                texture = nil
            }

            CVPixelBufferUnlockBaseAddress(movieFrame, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))

            if texture != nil {
                self.updateTargetsWithTexture(texture!)
            }
            
            if self.runBenchmark {
                let currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime)
                self.numberOfFramesCaptured += 1
                self.totalFrameTimeDuringCapture += currentFrameTime
                print("Average frame time : \(1000.0 * self.totalFrameTimeDuringCapture / Double(self.numberOfFramesCaptured)) ms")
                print("Current frame time : \(1000.0 * currentFrameTime) ms")
            }
        }

        public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
            // Not needed for movie inputs
        }
    }
