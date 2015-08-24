//
//  ViewController.m
//  RtspStreamer
//
//  Created by Victor on 04.08.15.
//  Copyright (c) 2015 Company. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "Reachability.h"

@implementation ViewController
{
    RtspAudioPlayer *player;
    BOOL isPlaying;
    dispatch_queue_t queue;
    long missedPacketCount;
    long reconnectCount;
    double trafficCount;
    
    __weak IBOutlet UILabel *trafficLabel;
    __weak IBOutlet UILabel *packetLossLabel;
    __weak IBOutlet UILabel *reconnectLabel;
    
    Reachability* reachability;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    missedPacketCount = 0;
    trafficCount = 0;
    reconnectCount = -1;
    
//    [AVAudioSession sharedInstance];
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:) name:AVAudioSessionRouteChangeNotification object:nil];
    
    queue = dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(restartStream) name:@"restartStream" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNetworkChange:) name:kReachabilityChangedNotification object:nil];
    reachability = [Reachability reachabilityForInternetConnection];
    [reachability startNotifier];
    
//    if (![self isHeadsetPluggedIn]) {
//        NSLog(@"Stream will start when headphones plugged-in");
//    } else {
        [self restartStream];
//    };
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
}

- (void) trafficUpdate:(float)traffic
{
    trafficCount += traffic;
    trafficLabel.text = [NSString stringWithFormat:@"traffic: %.0f Kb (%.1f Kb/s)", trafficCount, traffic];
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
//    if ([self isHeadsetPluggedIn])
//    {
        player = [[RtspAudioPlayer alloc] initWithUrl:@"rtsp://192.168.1.30:1935/live/myStream"];
        player.delegate = self;
        [player play];
        player = nil;
    
        dispatch_async(dispatch_get_main_queue(), ^{
            self.view.backgroundColor = [UIColor redColor];
            [self packetLost:0];
        });

//    }
//    else
//    {
//        NSLog(@"Stream will start when headphones plugged-in");
//    }
}

- (void)restartStream
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self restartStreamWithDelay];
    });
}

- (void) restartStreamWithDelay
{
    self.view.backgroundColor = [UIColor whiteColor];
    dispatch_async(queue, ^{
        [self connectStream];
        
    });
}

// Headphones checker
//- (BOOL)isHeadsetPluggedIn {
//    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
//    for (AVAudioSessionPortDescription* desc in [route outputs]) {
//        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
//            return YES;
//    }
//    return NO;
//}

//- (void)audioRouteChangeListenerCallback:(NSNotification*)notification
//{
//    NSDictionary *interuptionDict = notification.userInfo;
//    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
//    switch (routeChangeReason)
//    {
//        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
//            NSLog(@"Headphones plugged in, playing");
//            [self restartStream];
//            break;
//            
//        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
//            NSLog(@"Headphones was pulled, disconnecting");
//            [player stop];
//            break;
//    }
//}

- (void) handleNetworkChange:(NSNotification *)notice
{
    NetworkStatus remoteHostStatus = [reachability currentReachabilityStatus];
    
    if (remoteHostStatus != ReachableViaWiFi) {
        [self packetLost:1];
        self.view.backgroundColor = [UIColor redColor];
    } else {
        self.view.backgroundColor = [UIColor whiteColor];
    }
}


@end
