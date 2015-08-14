//
//  ViewController.m
//  RtspStreamer
//
//  Created by Victor on 04.08.15.
//  Copyright (c) 2015 Company. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

@implementation ViewController
{
    RtspAudioPlayer *player;
    BOOL isPlaying;
    dispatch_queue_t queue;
    long missedPacketCount;
    long reconnectCount;
    
    __weak IBOutlet UILabel *trafficLabel;
    __weak IBOutlet UILabel *packetLossLabel;
    __weak IBOutlet UILabel *reconnectLabel;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    missedPacketCount = 0;
    reconnectCount = 0;
    
    [AVAudioSession sharedInstance];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:) name:AVAudioSessionRouteChangeNotification object:nil];
    
    queue = dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(restartStream) name:@"restartStream" object:nil];
    
    if (![self isHeadsetPluggedIn]) {
        NSLog(@"Stream will start when headphones plugged-in");
    } else {
        [self connectStream];
    };
}

- (void) trafficUpdate:(float)traffic
{
    trafficLabel.text = [NSString stringWithFormat:@"traffic: %.1f kbps", traffic];
}

- (void) packetLost:(int)lostPackets
{
    reconnectCount += 1;
    missedPacketCount += lostPackets;
    packetLossLabel.text = [NSString stringWithFormat:@"missed: %ld packets", missedPacketCount];
    reconnectLabel.text = [NSString stringWithFormat:@"reconnects: %ld", reconnectCount];
}

- (void)connectStream
{
    if ([self isHeadsetPluggedIn])
    {
        player = [[RtspAudioPlayer alloc] initWithUrl:@"rtsp://192.168.1.30:1935/live/myStream"];
        player.delegate = self;
        [player play];
        player = nil;
    }
    else
    {
        NSLog(@"Stream will start when headphones plugged-in");
    }
}

- (void)restartStream
{
    dispatch_async(queue, ^{
         [self connectStream];
    });
}

// Headphones checker
- (BOOL)isHeadsetPluggedIn {
    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
            return YES;
    }
    return NO;
}

- (void)audioRouteChangeListenerCallback:(NSNotification*)notification
{
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    switch (routeChangeReason)
    {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            NSLog(@"Headphones plugged in, playing");
            [self restartStream];
            break;
            
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            NSLog(@"Headphones was pulled, disconnecting");
            [player stop];
            break;
    }
}


@end
