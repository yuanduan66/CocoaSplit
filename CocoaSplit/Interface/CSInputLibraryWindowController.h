//
//  CSInputLibraryWindowController.h
//  CocoaSplit
//
//  Created by Zakk on 10/18/15.
//  Copyright © 2015 Zakk. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class CaptureController;

@interface CSInputLibraryWindowController : NSWindowController <NSTableViewDelegate>

@property (strong) CaptureController *controller;
@property (weak) IBOutlet NSTableView *tableView;
@property (strong) NSMutableArray *tableControllers;
@property (strong) IBOutlet NSArrayController *itemArrayController;

@end