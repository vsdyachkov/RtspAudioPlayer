//
//  ViewController.m
//  RtspStreamer
//
//  Created by Victor on 04.08.15.
//  Copyright (c) 2015 Company. All rights reserved.
//

#import "ViewController.h"
#import "RtspAudioPlayer.h"

@implementation ViewController
{
    RtspAudioPlayer *player;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self connectStream];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectStream) name:@"restartStream" object:nil];
}

- (void) connectStream
{
    player = nil;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        player = [[RtspAudioPlayer alloc] initWithUrl:@"rtsp://192.168.1.30:1935/live/myStream"];
        [player play];
        NSLog(@"Finished play");
    });
}


@end
