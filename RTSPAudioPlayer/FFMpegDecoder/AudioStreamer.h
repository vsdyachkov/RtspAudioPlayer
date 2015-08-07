//



#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "RTSPPlayer.h"

#define kNumAQBufs 3
#define kAudioBufferSeconds 3

typedef enum _AUDIO_STATE {
    AUDIO_STATE_READY           = 0,
    AUDIO_STATE_STOP            = 1,
    AUDIO_STATE_PLAYING         = 2,
    AUDIO_STATE_PAUSE           = 3,
    AUDIO_STATE_SEEKING         = 4
} AUDIO_STATE;

@interface AudioStreamer : NSObject

@property (nonatomic) AVCodecContext* audioCodecContext;

- (void) startAudio;
- (void) enqueueBuffer:(AudioQueueBufferRef)buffer;
- (instancetype) initWithStreamer:(RTSPPlayer*)streamer;

@end
