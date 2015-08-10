//
//  ViewController.m
//  RtspStreamer
//
//  Created by Victor on 04.08.15.
//  Copyright (c) 2015 Company. All rights reserved.
//

#import "ViewController.h"
#import "RTSPPlayer.h"

@implementation ViewController
{
    RTSPPlayer *player;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self connectStream];
//    });
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectStream) name:@"restartStream" object:nil];
}

- (void) connectStream
{
    player = nil;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        player = [[RTSPPlayer alloc] initWithRtspAudioUrl:@"rtsp://192.168.1.30:1935/live/myStream"];
        [player play];
        NSLog(@"Finished play");
    });
}


@end
