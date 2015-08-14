//
//  ViewController.m
//  RtspStreamer
//
//  Created by Victor on 04.08.15.
//  Copyright (c) 2015 Company. All rights reserved.
//

#import "ViewController.h"
#import "Reachability.h"

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
    
    Reachability* reachability;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    missedPacketCount = 0;
    reconnectCount = 0;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNetworkChange:) name:kReachabilityChangedNotification object:nil];
    reachability = [Reachability reachabilityForInternetConnection];
    [reachability startNotifier];
    
    queue = dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(restartStream) name:@"restartStream" object:nil];
    dispatch_async(queue, ^{
        [self connectStream];
    });
}

- (void) handleNetworkChange:(NSNotification *)notice
{
    NetworkStatus remoteHostStatus = [reachability currentReachabilityStatus];
    
    if (remoteHostStatus != ReachableViaWiFi) {
        [self packetLost:1];
    }
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
    player = [[RtspAudioPlayer alloc] initWithUrl:@"rtsp://192.168.1.30:1935/live/myStream"];
    player.delegate = self;
    [player play];
    player = nil;
}

- (void)restartStream
{
    dispatch_async(queue, ^{
         [self connectStream];
    });
}


@end
