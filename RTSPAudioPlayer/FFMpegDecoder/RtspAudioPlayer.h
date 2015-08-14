//
//  RTSPPlayer.h
//  RtspStreamer
//
//  Created by Victor on 04.08.15.
//  Copyright (c) 2015 Company. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol RtspAudioPlayerProtocol <NSObject>

- (void) packetLost:(int)lostPackets;
- (void) trafficUpdate:(float)traffic;

@end

@interface RtspAudioPlayer : NSObject

- (id) initWithUrl:(NSString *)url;
- (void) play;

@property (nonatomic, strong) id <RtspAudioPlayerProtocol> delegate;

@end

