//
//  CSSequenceActivatorViewController.h
//  CocoaSplit
//
//  Created by Zakk on 3/12/17.
//  Copyright © 2017 Zakk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CSSequenceActivatorView.h"

@interface CSSequenceActivatorViewController : NSViewController
@property (strong) NSArray *sequences;
@property (strong) NSMenu *sequenceMenu;
@property (strong) NSMutableArray *queuedSequences;


-(void)showSequenceMenu:(NSEvent *)clickEvent forView:(CSSequenceActivatorView *)view;
-(void)sequenceViewClicked:(NSEvent *)clickEvent forView:(CSSequenceActivatorView *)view;


@end
