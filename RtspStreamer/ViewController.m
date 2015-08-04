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
    
    player = [[RTSPPlayer alloc] initWithRtspAudioUrl:@"rtsp://192.168.1.30:1935/live/myStream"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [player play];
        NSLog(@"Session closed");
    });
}


@end
