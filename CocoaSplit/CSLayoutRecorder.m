//
//  CSLayoutRecorder.m
//  CocoaSplit
//
//  Created by Zakk on 4/30/17.
//  Copyright © 2017 Zakk. All rights reserved.
//

#import "CSLayoutRecorder.h"
#import "CaptureController.h"

@implementation CSLayoutRecorder



-(instancetype) init
{
    if (self = [super init])
    {
        _outputs = [NSMutableArray array];
        _compressors = [NSMutableDictionary dictionary];
    }
    return self;
}


-(float)frameRate
{
    if (self.layout)
    {
        return self.layout.frameRate;
    }
    
    return 0.0f;
}


-(void)checkOutputs
{
    if (self.outputs.count == 0)
    {
        self.layout.recorder = nil;
        self.layout.isActive = NO;
        self.recordingActive = NO;
        [self.audioEncoder stopEncoder];
        self.audioEngine.encoder = nil;
        self.audioEngine = nil;
        [[CaptureController sharedCaptureController] removeLayoutRecorder:self];
    }
}




-(void)stopRecordingAll
{
    
    NSArray *outCopy = self.outputs.copy;
    
    for (OutputDestination *dest in outCopy)
    {
        [self stopRecordingForOutput:dest];
    }
    
    if (self.output)
    {
        [self stopDefaultRecording];
    }
}


-(void)startRecordingWithOutput:(OutputDestination *)output
{
    
    if (![self.outputs containsObject:output])
    {
        [self.outputs addObject:output];
    }
    
    output.settingsController = self;

    output.captureRunning = YES;

    [output setup];
    
    //[output setupCompressor];
    if (!self.recordingActive)
    {
    
        [self startRecordingCommon];
    }
    
}

-(void)stopRecordingForOutput:(OutputDestination *)output
{
    OutputDestination *useOut;
    
    for (OutputDestination *tmpOut in self.outputs)
    {
        if (tmpOut == output)
        {
            useOut = tmpOut;
        }
    }
    
    if (useOut)
    {
        useOut.captureRunning = NO;

        [useOut stopOutput];
        [useOut reset];
        
        [self.outputs removeObject:useOut];
        [self checkOutputs];

    }
}


-(void)startRecording
{
    
    self.useTimestamp = YES;

    CaptureController *captureController = [CaptureController sharedCaptureController];

    OutputDestination *newOutput;
    newOutput = [[OutputDestination alloc] init];
    newOutput.settingsController = self;
    newOutput.streamServiceObject = (id<CSStreamServiceProtocol>)self;
    //NSObject<VideoCompressor> *origCompressor = [captureController compressorByName:captureController.layoutRecorderCompressorName];
    newOutput.compressor_name = captureController.layoutRecorderCompressorName;
    
    //newOutput.compressor = origCompressor.copy;
    newOutput.settingsController = self;
    
    NSString *baseDir = captureController.layoutRecordingDirectory;
    NSString *fileFormat = captureController.layoutRecordingFormat;
    newOutput.captureRunning = YES;
    newOutput.active = YES;

    self.output = newOutput;
    self.outputFilename = [baseDir stringByAppendingString:[NSString stringWithFormat:@"/%@.%@", self.layout.name, fileFormat]];
    self.fileFormat = fileFormat;
    
    [self.outputs addObject:newOutput];
    [self startRecordingCommon];
    self.defaultRecordingActive = YES;
    self.layout.recordingLayout = YES;
}


-(void)stopDefaultRecording
{
    if (self.output)
    {
        self.layout.recordingLayout = NO;
        self.output.active = NO;
        self.output.captureRunning = NO;
        [self.outputs removeObject:self.output];
        [self checkOutputs];
    }
}


-(void)startRecordingCommon
{
    
    

    
    if (!self.recordingActive)
    {
        _firstAudioTime = kCMTimeZero;
        _previousAudioTime = kCMTimeZero;
        _firstPcmAudioTime = kCMTimeZero;
        _previousPcmAudioTime = kCMTimeZero;
        
        
        _audioBuffer = [NSMutableArray array];
        _pcmAudioBuffer = [NSMutableArray array];


        
        
        
        
        if (!self.audioEngine)
        {
        
            CAMultiAudioEngine *useEngine = nil;


            useEngine = self.layout.audioEngine;
            
            if (!useEngine)
            {
                useEngine = [[CAMultiAudioEngine alloc] init];
                useEngine.sampleRate = [CaptureController sharedCaptureController].multiAudioEngine.sampleRate;
                [useEngine disableAllInputs];
            }
            

            self.audioEncoder = [[CSAacEncoder alloc] init];
            self.audioEncoder.encodedReceiver = self;
            self.audioEncoder.sampleRate = [CaptureController sharedCaptureController].multiAudioEngine.sampleRate;
            self.audioEncoder.bitRate = [CaptureController sharedCaptureController].multiAudioEngine.audioBitrate*1000;
            
            self.audioEncoder.inputASBD = useEngine.graph.graphAsbd;
            [self.audioEncoder setupEncoderBuffer];
            useEngine.encoder = self.audioEncoder;
            useEngine.previewMixer.muted = YES;
            self.audioEngine = useEngine;
            
        } else {
            self.audioEncoder = self.audioEngine.encoder;
        }
        
        
        if (!self.renderer)
        {
            self.renderer = [[LayoutRenderer alloc] init];
        }
        if (self.layout.sourceList.count == 0)
        {
            [self.layout restoreSourceList:nil];
        } else {
            [self.layout reapplyAudioSources];
        }
        
        self.renderer.layout = self.layout;
        
        if (!_frame_queue)
        {
            _frame_queue = dispatch_queue_create("layout.recorder.queue", DISPATCH_QUEUE_SERIAL);
        }
        
        
        self.layout.recorder = self;
        
        self.recordingActive = YES;
        self.layout.isActive = YES;

        dispatch_async(_frame_queue, ^{
            [self newFrameTimed];
            
        });
    }
    
    
}





-(NSObject<VideoCompressor> *)compressorByName:(NSString *)name
{
    NSObject<VideoCompressor> *compressor = nil;
    
    compressor = self.compressors[name];
    
    if (!compressor || [compressor isEqualTo:[NSNull null]])
    {
        NSObject<VideoCompressor> *origCompressor =  [CaptureController sharedCaptureController].compressors[name];
        compressor = origCompressor.copy;
        self.compressors[compressor.name] = compressor;
    }
    
    return compressor;
}


-(NSString *)getServiceFormat
{
    return self.fileFormat;
}



-(NSString *)getServiceDestination
{
    NSString *useFilename = self.outputFilename;
    NSString *pathExt = [self.outputFilename pathExtension];
    NSString *noExt = [useFilename stringByDeletingPathExtension];
    
    if (self.useTimestamp)
    {
        NSDateFormatter *dFormat = [[NSDateFormatter alloc] init];
        dFormat.dateFormat = @"yyyyMMddHHmmss";
        NSString *dateStr = [dFormat stringFromDate:[NSDate date]];
        useFilename = [NSString stringWithFormat:@"%@-%@.%@", noExt, dateStr, pathExt];
    }
    
    if (self.noClobber)
    {
        noExt = [useFilename stringByDeletingPathExtension];
        
        NSFileManager *fManager = [[NSFileManager alloc] init];
        NSString *noExt = [useFilename stringByDeletingPathExtension];
        int fidx = 1;
        while ([fManager fileExistsAtPath:useFilename])
        {
            useFilename = [NSString stringWithFormat:@"%@-%d.%@", noExt, fidx, pathExt];
            fidx++;
        }
    }
    return useFilename;
}



-(void)prepareForStreamStart
{
    return;
}


-(void)newFrameEvent
{
    _frame_time = [self mach_time_seconds];
    [self newFrame];
}


-(void)frameArrived:(id)ctx
{
    dispatch_async(_frame_queue, ^{
        if (self.recordingActive)
        {
            [self newFrameEvent];
        }
    });
}

-(void)frameTimerWillStop:(id)ctx
{
    dispatch_async(_frame_queue, ^{
        [self newFrameTimed];
    });
}


-(void) newFrameTimed
{
    
    double startTime;
    
    startTime = [[CaptureController sharedCaptureController] mach_time_seconds];
    
    _frame_time = startTime;
    _firstFrameTime = startTime;
    
    [self newFrame];
    
    while (1)
    {
        @autoreleasepool {
            
    
        if (self.layout.layoutTimingSource && self.layout.layoutTimingSource.videoInput && self.layout.layoutTimingSource.videoInput.canProvideTiming)
        {
            CSCaptureBase *newTiming = (CSCaptureBase *)self.layout.layoutTimingSource.videoInput;
            newTiming.timerDelegateCtx = nil;
            newTiming.timerDelegate = self;
            return;
        }
        
        
        
        
        //_frame_time = nowTime;//startTime;
        
        
        if (![[CaptureController sharedCaptureController] sleepUntil:(startTime += 1.0/self.layout.frameRate)])
        {
            //NSLog(@"MISSED FRAME!");
            continue;
        }
        
        
        int drain_cnt = 0;
        if (!self.recordingActive)
        {
            
            for (OutputDestination *outdest in self.outputs)
            {
                if (outdest.buffer_draining)
                {
                    drain_cnt++;
                }
                [outdest writeEncodedData:nil];
            }
            
            if (!drain_cnt)
            {
                
                return;
            }
        }

        
        _frame_time = startTime;

            [self newFrame];
        
    }
    }
}

-(void) newFrame
{
    
    CVPixelBufferRef newFrame;
    
    //double nfstart = [self mach_time_seconds];
    
    newFrame = [self.renderer currentImg];
    
    if (self.frameReadyBlock)
    {
        self.frameReadyBlock();
    }
    
    /*
    double nfdone = [self mach_time_seconds];
    double nftime = nfdone - nfstart;
    _renderedFrames++;
    
    _render_time_total += nftime;
    if (nftime < _min_render_time || _min_render_time == 0.0f)
    {
        _min_render_time = nftime;
    }
    
    if (nftime > _max_render_time)
    {
        _max_render_time = nftime;
    }
    */
    
    
    if (newFrame)
    {
        _frameCount++;
        CVPixelBufferRetain(newFrame);
        NSMutableArray *frameAudio = [[NSMutableArray alloc] init];
        NSMutableArray *pcmFrameAudio = [[NSMutableArray alloc] init];

        [self setAudioData:frameAudio videoPTS:CMTimeMake((_frame_time - _firstFrameTime)*1000, 1000)];
        [self setPcmAudioData:pcmFrameAudio videoPTS:CMTimeMake((_frame_time - _firstFrameTime)*1000, 1000)];

        
        CapturedFrameData *newData = [self createFrameData];
        newData.audioSamples = frameAudio;
        newData.videoFrame = newFrame;
        newData.pcmAudioSamples = pcmFrameAudio;
        
        int used_compressor_count = 0;
        
        for(id cKey in self.compressors)
        {
            
            id <VideoCompressor> compressor;
            compressor = self.compressors[cKey];
            
            CapturedFrameData *newFrameData = newData.copy;
            
            [compressor compressFrame:newFrameData];
            if ([compressor hasOutputs])
            {
                used_compressor_count++;
            }
        }

        CVPixelBufferRelease(newFrame);
        if (used_compressor_count == 0)
        {
            //[self stopRecordingAll];
        }
        
    }
}

-(CapturedFrameData *)createFrameData
{
    
    CMTime pts = CMTimeMake((_frame_time - _firstFrameTime)*1000, 1000);
    
    CMTime duration = CMTimeMake(1, self.layout.frameRate);
    
    CapturedFrameData *newFrameData = [[CapturedFrameData alloc] init];
    newFrameData.videoPTS = pts;
    newFrameData.videoDuration = duration;
    newFrameData.frameNumber = _frameCount;
    newFrameData.frameTime = _frame_time;
    return newFrameData;
}


-(CFAbsoluteTime) mach_time_seconds
{
    return [[CaptureController sharedCaptureController] mach_time_seconds];
}


-(void) addPcmAudioData:(CMSampleBufferRef)audioData
{
    
    @synchronized(self)
    {
        
        [_pcmAudioBuffer addObject:(__bridge id)audioData];
    }
}


-(void) addAudioData:(CMSampleBufferRef)audioData
{
    
    @synchronized(self)
    {

        [_audioBuffer addObject:(__bridge id)audioData];
    }
}


-(void)setPcmAudioData:(NSMutableArray *)audioDestination videoPTS:(CMTime)videoPTS
{
    NSUInteger audioConsumed = 0;
    NSUInteger sampleCount = 0;
    
    NSMutableArray *pendingConsume = [NSMutableArray array];
    
    @synchronized(self)
    {
        NSUInteger audioBufferSize = [_pcmAudioBuffer count];
        
        for (int i = 0; i < audioBufferSize; i++)
        {
            CMSampleBufferRef audioData = (__bridge CMSampleBufferRef)[_pcmAudioBuffer objectAtIndex:i];
            
            CMTime audioTime = CMSampleBufferGetOutputPresentationTimeStamp(audioData);
            
            
            
            
            if (CMTIME_COMPARE_INLINE(audioTime, <=, videoPTS))
            {
                sampleCount += CMSampleBufferGetNumSamples(audioData);
                audioConsumed++;
                [audioDestination addObject:(__bridge id)audioData];
            } else {
                break;
            }
        }
        
        if (audioConsumed > 0)
        {
            [_pcmAudioBuffer removeObjectsInRange:NSMakeRange(0, audioConsumed)];
        }
        
    }
}

-(void) setAudioData:(NSMutableArray *)audioDestination videoPTS:(CMTime)videoPTS
{
    
    NSUInteger audioConsumed = 0;
    @synchronized(self)
    {
        NSUInteger audioBufferSize = [_audioBuffer count];
        
        for (int i = 0; i < audioBufferSize; i++)
        {
            CMSampleBufferRef audioData = (__bridge CMSampleBufferRef)[_audioBuffer objectAtIndex:i];
            
            CMTime audioTime = CMSampleBufferGetOutputPresentationTimeStamp(audioData);
            
            
            
            
            if (CMTIME_COMPARE_INLINE(audioTime, <=, videoPTS))
            {
                
                audioConsumed++;
                [audioDestination addObject:(__bridge id)audioData];
            } else {
                break;
            }
        }
        
        if (audioConsumed > 0)
        {
            [_audioBuffer removeObjectsInRange:NSMakeRange(0, audioConsumed)];
        }
        
    }
}

-(void)captureOutputAudio:(id)fromDevice didOutputPCMSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    if (!self.recordingActive)
    {
        return;
    }
    
    
    CMTime orig_pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    
    
    
    if (CMTIME_COMPARE_INLINE(_firstPcmAudioTime, ==, kCMTimeZero))
    {
        
        
        _firstPcmAudioTime = orig_pts;
        return;
    }
    
    
    CMTime pts = CMTimeSubtract(orig_pts, _firstPcmAudioTime);
    //CMTime adjust_pts = CMTimeMakeWithSeconds(self.audio_adjust, orig_pts.timescale);
    //CMTime pts = CMTimeAdd(real_pts, adjust_pts);
    
    
    
    CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, pts);
    
    if (CMTIME_COMPARE_INLINE(pts, >, _previousPcmAudioTime))
    {
        if (sampleBuffer)
        {
            [self addPcmAudioData:sampleBuffer];
        }
        _previousPcmAudioTime = pts;
    }
}


- (void)captureOutputAudio:(id)fromDevice didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer 
{
    
    
    if (!self.recordingActive)
    {
        return;
    }
    
    
    CMTime orig_pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    
    
    
    if (CMTIME_COMPARE_INLINE(_firstAudioTime, ==, kCMTimeZero))
    {
        
        
        _firstAudioTime = orig_pts;
        return;
    }
    
    
    CMTime pts = CMTimeSubtract(orig_pts, _firstAudioTime);
    //CMTime adjust_pts = CMTimeMakeWithSeconds(self.audio_adjust, orig_pts.timescale);
    //CMTime pts = CMTimeAdd(real_pts, adjust_pts);
    
    
    
    CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, pts);
    
    if (CMTIME_COMPARE_INLINE(pts, >, _previousAudioTime))
    {
        if (sampleBuffer)
        {
            [self addAudioData:sampleBuffer];
        }
        _previousAudioTime = pts;
    }
}


@end
