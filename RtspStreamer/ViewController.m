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
    BOOL isPlaying;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(restartStream) name:@"restartStream" object:nil];
    [self connectStream];
}

- (void)connectStream
{
    player = [[RtspAudioPlayer alloc] initWithUrl:@"rtsp://192.168.1.30:1935/live/myStream"];
    [player play];
    player = nil;
}

- (void)restartStream
{
    //dispatch_async(dispatch_get_main_queue(), ^{
         [self connectStream];
    //});
}


@end
