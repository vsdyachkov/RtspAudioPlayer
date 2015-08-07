//



#import <Foundation/Foundation.h>
#import "avformat.h"
#import "avcodec.h"
#import "avio.h"
#import "swscale.h"
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioToolbox.h>

@interface RTSPPlayer : NSObject

@property (nonatomic, retain) NSMutableArray *audioPacketQueue;
@property (nonatomic, assign) int audioPacketQueueSize;

@property (nonatomic, assign) AVCodecContext* audioCodecContext;
@property (nonatomic, assign) AudioQueueBufferRef emptyAudioBuffer;
@property (nonatomic, assign) AVStream* audioStream;

- (AVPacket*) readPacket;


/* ---------------------- */


/* Initialize with RTSP audio url string */
- (id) initWithRtspAudioUrl:(NSString *)url;

/* Play audio in main thread */
- (void) play;

@end
