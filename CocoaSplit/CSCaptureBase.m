//
//  CaptureBase.m
//  CocoaSplit
//
//  Created by Zakk on 7/21/14.
//  Copyright (c) 2014 Zakk. All rights reserved
//

#import "CSCaptureBase.h"
#import "CSTimerSourceProtocol.h"
#import "InputSource.h"
#import "CSNotifications.h"
#import "CSPcmPlayer.h"
#import "CaptureController.h"
#import "CSLayoutRecorder.h"

#import "SourceCache.h"
#import <objc/runtime.h>

@interface CSCaptureBase()
{
    
    //NSPointerArray *_allInputs;
    
    NSMapTable *_allLayers;
    frame_render_behavior _saved_render_behavior;
    CFAbsoluteTime _fps_start_time;
    int _fps_frame_cnt;

}


@property (weak) id<CSTimerSourceProtocol> timerDelegate;
@property (weak) id timerDelegateCtx;
@property (assign) CGFloat detectedInputWidth;
@property (assign) CGFloat detectedInputHeight;
@property (assign) double layerUpdateFPS;
@property (weak) InputSource *tickInput;

@end


@implementation CSCaptureBase

@synthesize activeVideoDevice = _activeVideoDevice;
@synthesize allowScaling = _allowScaling;
@synthesize timerDelegate = _timerDelegate;


+(NSString *) label
{
    return NSStringFromClass(self);
}

-(NSString *)instanceLabel
{
    return [self.class label];
}


-(instancetype) init
{
    if (self = [super init])
    {
        self.canProvideTiming = NO;
        self.needsSourceSelection = YES;
        self.allowDedup = YES;
        self.isVisible = YES;
        self.allowScaling = YES;
        _allLayers = [NSMapTable weakToStrongObjectsMapTable];
        
        _fps_start_time = CFAbsoluteTimeGetCurrent();
        _fps_frame_cnt = 0;
        
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStatistics:) name:CSNotificationStatisticsUpdate object:nil];
    }
    
    return self;
}

-(void)updateStatistics:(NSNotification *)notification
{
    CFAbsoluteTime time_now = CFAbsoluteTimeGetCurrent();
    
    NSSize detectedInputSize = [self captureSize];
    self.detectedInputWidth = detectedInputSize.width;
    self.detectedInputHeight = detectedInputSize.height;
    
    
    self.layerUpdateFPS = _fps_frame_cnt / (time_now - _fps_start_time);
    
    _fps_frame_cnt = 0;
    _fps_start_time = time_now;
}


-(void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.activeVideoDevice.uniqueID forKey:@"active_uniqueID"];
    [aCoder encodeBool:self.allowDedup forKey:@"allowDedup"];
}


-(id) initWithCoder:(NSCoder *)aDecoder
{
    if (self = [self init])
    {
     
        self.allowDedup = [aDecoder decodeBoolForKey:@"allowDedup"];
        self.savedUniqueID = [aDecoder decodeObjectForKey:@"active_uniqueID"];
        [self setDeviceForUniqueID:self.savedUniqueID];
    }
    
    return self;
}



-(NSImage *)libraryImage
{
    return nil;
}


-(NSString *) configurationViewClassName
{
    return [NSString stringWithFormat:@"%@ViewController", self.className];
}


-(NSString *) configurationViewName
{
    return [NSString stringWithFormat:@"%@ViewController", self.className];
}



-(NSViewController *)configurationView
{
    
    NSViewController *configViewController;
    
    NSString *controllerName = self.configurationViewClassName;
    
    
    
    
    Class viewClass = NSClassFromString(controllerName);
    
    if (viewClass)
    {
        
        
        configViewController = [[viewClass alloc] initWithNibName:self.configurationViewName bundle:[NSBundle bundleForClass:self.class]];
        
        if (configViewController)
        {
            
            //Should probably make a base class for view controllers and put captureObj there
            //but for now be gross.
            [configViewController setValue:self forKey:@"captureObj"];
        }
    }
    return configViewController;
    
}


-(void)setDeviceForUniqueID:(NSString *)uniqueID
{
    
    CSAbstractCaptureDevice *dummydev = [[CSAbstractCaptureDevice alloc] init];
    
    dummydev.uniqueID = uniqueID;
    
    NSArray *currentAvailableDevices;
    
    currentAvailableDevices = self.availableVideoDevices;
    
    NSUInteger sidx;
    sidx = [currentAvailableDevices indexOfObject:dummydev];
    
    if (sidx == NSNotFound)
    {
        self.activeVideoDevice = nil;
    } else {
        
        self.activeVideoDevice = [currentAvailableDevices objectAtIndex:sidx];
    }
}

-(void)frameTickFromInput:(InputSource *)input
{
    [self frameTick];
}


-(void)frameTick
{
    return;
}


-(void)willDelete
{
    return;
}


-(float)render_height
{
    NSNumber *ret = [self.inputSource valueForKeyPath:@"display_height"];
    return [ret intValue];
}

-(float)render_width
{
    
    NSNumber *ret = [self.inputSource valueForKeyPath:@"display_width"];
    return [ret intValue];
}


-(NSSize)captureSize
{
    return NSZeroSize;
}


-(id) copyWithZone:(NSZone *)zone
{
  
    
    id newCopy = [[self.class alloc] init];
    
    
    
    //This is gross I'm sorry
    
    unsigned int propCount;
    Class currentClass = self.class;
    
    
    while (currentClass && [currentClass superclass])
    {
        
        
    
        objc_property_t *myProperties = class_copyPropertyList(currentClass, &propCount);
        for (unsigned int i = 0; i < propCount; i++)
        {
            objc_property_t prop = myProperties[i];
            const char *propName = property_getName(prop);
            
            NSString *pName = [[NSString alloc] initWithBytes:propName length:strlen(propName) encoding:NSUTF8StringEncoding];
            id propertyValue = [self valueForKey:pName];
            
            [newCopy setValue:propertyValue forKey:pName];
        }
        
        currentClass = [currentClass superclass];
        
        
    }
    return newCopy;
    
}

-(void) setValue:(id)value forUndefinedKey:(NSString *)key
{
    //hack so we don't throw exceptions during the above function
    return;
}




-(CALayer *)createNewLayer
{
    CALayer *newLayer = [CALayer layer];
    return newLayer;

}


-(CALayer *)createNewLayerForInput:(id)inputsrc
{
    

    CALayer *newLayer = [self createNewLayer];
    @synchronized(self)
    {
        if (!self.tickInput)
        {
            self.tickInput = inputsrc;
        }
        
        
        //[_allInputs addObject:inputsrc];
        
        [_allLayers setObject:newLayer forKey:inputsrc];
    }

    return newLayer;
}

-(void)removeLayerForInput:(id)inputsrc
{
    @synchronized(self)
    {
        if (self.tickInput == inputsrc)
        {
            self.tickInput = nil;
            
        }

        
        [_allLayers removeObjectForKey:inputsrc];
        
        if (!self.tickInput)
        {
            for (id key in _allLayers)
            {
                if (key)
                {
                    self.tickInput = key;
                }
            }
        }
        
        
        if (_allLayers.count == 0)
        {
            [self willDelete];
        }
    }
}



-(void)updateLayersWithFramedataBlock:(void (^)(CALayer *))updateBlock withPreuseBlock:(void(^)(void))preUseBlock withPostuseBlock:(void(^)(void))postUseBlock
{
    [self internalUpdateLayerswithFrameData:true updateBlock:updateBlock preBlock:preUseBlock postBlock:postUseBlock];

}

-(void)updateLayersWithFramedataBlock:(void(^)(CALayer *))updateBlock
{
    

    [self internalUpdateLayerswithFrameData:true updateBlock:updateBlock preBlock:nil postBlock:nil];

}

-(void)updateLayersWithBlock:(void (^)(CALayer *layer))updateBlock
{
    [self internalUpdateLayerswithFrameData:false updateBlock:updateBlock preBlock:nil postBlock:nil];
}

-(void)internalUpdateLayerswithFrameData:(bool) frameData updateBlock:(void (^)(CALayer *layer))updateBlock preBlock:(void(^)(void))preBlock postBlock:(void(^)(void))postBlock
{
    

    NSMapTable *inputsCopy = nil;
    @synchronized(self)
    {
        inputsCopy = _allLayers.copy;
    }
    
    if (frameData)
    {
        _fps_frame_cnt++;
    }
    

    for (id key in inputsCopy)
    {
        
        if (!key)
        {
            continue;
        }
        
        
        InputSource *layerSrc = (InputSource *)key;
        if (frameData)
        {
            [layerSrc updateLayersWithNewFrame:updateBlock withPreuseBlock:preBlock withPostuseBlock:postBlock];
        } else {
            [layerSrc updateLayer:updateBlock];
        }
    }
    


}

-(CSPcmPlayer *)createPCMInput:(NSString *)forUID withFormat:(const AudioStreamBasicDescription *)withFormat
{
    
    CAMultiAudioEngine *useEngine = nil;
    
    NSMapTable *inputsCopy = nil;
    @synchronized(self)
    {
        inputsCopy = _allLayers.copy;
    }
    

    for (id key in inputsCopy)
    {
        
        if (!key)
        {
            continue;
        }
        
        
        InputSource *layerSrc = (InputSource *)key;
        if (layerSrc && layerSrc.sourceLayout && layerSrc.sourceLayout.recorder && layerSrc.sourceLayout.recorder.audioEngine)
        {
            useEngine = layerSrc.sourceLayout.recorder.audioEngine;
        }
    }
    
    if (!useEngine)
    {
        useEngine = [CaptureController sharedCaptureController].multiAudioEngine;
    }
    
    
    if (useEngine)
    {
        
        CAMultiAudioPCMPlayer *player;
        
        player = [useEngine createPCMInput:forUID withFormat:withFormat];
        return (CSPcmPlayer *)player;
    }
    
    return nil;
}

-(void)frameArrived
{
    if (self.timerDelegate)
    {
        [self.timerDelegate frameArrived:self.timerDelegateCtx];
    }
}


-(void)setTimerDelegate:(id<CSTimerSourceProtocol>)timerDelegate
{
    if (timerDelegate)
    {
        _saved_render_behavior = self.renderType;
        self.renderType = kCSRenderFrameArrived;
    } else {
        self.renderType = _saved_render_behavior;
    }
    
    _timerDelegate = timerDelegate;
}

-(id<CSTimerSourceProtocol>)timerDelegate
{
    return _timerDelegate;
}


-(CALayer *)layerForInput:(id)inputsrc
{
    return [_allLayers objectForKey:inputsrc];
}

-(void)setAllowScaling:(bool)allowScaling
{
    _allowScaling = allowScaling;
    [self updateLayersWithBlock:^(CALayer *layer) {
        [layer setValue:@(!allowScaling) forKey:@"csnoResize"];
    }];
}

-(bool)allowScaling
{
    return _allowScaling;
}


+(bool)canCreateSourceFromPasteboardItem:(NSPasteboardItem *)item
{
    return NO;
}


+(void) layoutModification:(void (^)(void))modBlock
{
    //On main thread already, just execute the block, otherwise execute on main and wait
    if ([NSThread isMainThread])
    {
        modBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            modBlock();
        });
    }
    
}

-(void)willExport
{
    return;
}


-(void)didExport
{
    return;
}
-(void)dealloc
{
    if (self.timerDelegate)
    {
        [self.timerDelegate frameTimerWillStop:self.timerDelegateCtx];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.timerDelegate = nil;
}


+(NSObject <CSCaptureSourceProtocol> *)createSourceFromPasteboardItem:(NSPasteboardItem *)item
{
    return nil;
}

+(NSObject <CSCaptureSourceProtocol> *)createSourceFromPasteboardItem
{
    return nil;
}


+(NSSet *)mediaUTIs
{
    return nil;
}


@end
