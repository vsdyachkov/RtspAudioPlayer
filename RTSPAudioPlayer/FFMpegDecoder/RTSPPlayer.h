#import <Foundation/Foundation.h>
#import "avformat.h"
#import "avcodec.h"
#import "avio.h"
#import "swscale.h"
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioToolbox.h>

@interface RTSPPlayer : NSObject
{
	AVFormatContext *pFormatCtx;
	AVCodecContext *pCodecCtx;
    AVFrame *pFrame;
    AVPacket packet;
	AVPicture picture;
	int videoStream;
    int audioStream;
	struct SwsContext *img_convert_ctx;
//	int sourceWidth, sourceHeight;
//	int outputWidth, outputHeight;
//	UIImage *currentImage;
//	double duration;
//    double currentTime;
    NSLock *audioPacketQueueLock;
    AVCodecContext *_audioCodecContext;
    int16_t *_audioBuffer;
    int audioPacketQueueSize;
    NSMutableArray *audioPacketQueue;
    AVStream *_audioStream;
    NSUInteger _audioBufferSize;
    BOOL _inBuffer;
    AVPacket *_packet, _currentPacket;
    BOOL primed;
}

/* Last decoded picture as UIImage */
@property (nonatomic, readonly) UIImage *currentImage;

// Size of video frame 
@property (nonatomic, readonly) int sourceWidth, sourceHeight;

/* Output image size. Set to the source size by default. */
@property (nonatomic) int outputWidth, outputHeight;

/* Length of video in seconds */
@property (nonatomic, readonly) double duration;

/* Current time of video in seconds */
@property (nonatomic, readonly) double currentTime;

@property (nonatomic, retain) NSMutableArray *audioPacketQueue;
@property (nonatomic, assign) AVCodecContext *_audioCodecContext;
@property (nonatomic, assign) AudioQueueBufferRef emptyAudioBuffer;
@property (nonatomic, assign) int audioPacketQueueSize;
@property (nonatomic, assign) AVStream *_audioStream;

/* Seek to closest keyframe near specified time */
//-(void)seekTime:(double)seconds;

-(void)closeAudio;

- (AVPacket*)readPacket;


/* ---------------------- */


/* Initialize with RTSP audio url string */
- (id) initWithRtspAudioUrl:(NSString *)url;

/* Play audio in main thread */
- (BOOL) play;

@end
