#import "RTSPPlayer.h"
#import "Utilities.h"
#import "AudioStreamer.h"

#ifndef AVCODEC_MAX_AUDIO_FRAME_SIZE
# define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio
#endif

@interface RTSPPlayer ()
@property (nonatomic, retain) AudioStreamer *audioController;
@end

@implementation RTSPPlayer
{
    int64_t lastPts;
}

@synthesize audioController = _audioController;
@synthesize audioPacketQueue,audioPacketQueueSize;
@synthesize _audioStream,_audioCodecContext;
@synthesize emptyAudioBuffer;


- (id) initWithRtspAudioUrl:(NSString *)url
{
    return [self initWithVideo:url usesTcp:NO];
}

- (id)initWithVideo:(NSString *)moviePath usesTcp:(BOOL)usesTcp
{
	if (!(self=[super init])) return nil;
 
//    AVCodec         *pCodec;
		
    // Register all formats and codecs
    avcodec_register_all();
    av_register_all();
    avformat_network_init();
    
    // Set the RTSP Options
    AVDictionary *opts = 0;
    if (usesTcp) 
        av_dict_set(&opts, "rtsp_transport", "tcp", 0);

    
    if (avformat_open_input(&pFormatCtx, [moviePath UTF8String], NULL, &opts) !=0 ) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
        return nil;
    }
    
    // Retrieve stream information
    if (avformat_find_stream_info(pFormatCtx,NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't find stream information\n");
        return nil;
    }
    
    // Find the first audio stream
    audioStream=-1;

    for (int i=0; i<pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO) {
            audioStream=i;
            NSLog(@"found audio stream");
        }
    }
    
    if (audioStream==-1) {
        return nil;
    } else {
        NSLog(@"set up audiodecoder");
        [self setupAudioDecoder];
    }

	return self;
}

//- (void)seekTime:(double)seconds
//{
//	AVRational timeBase = pFormatCtx->streams[videoStream]->time_base;
//	int64_t targetFrame = (int64_t)((double)timeBase.den / timeBase.num * seconds);
//	avformat_seek_file(pFormatCtx, videoStream, targetFrame, targetFrame, targetFrame, AVSEEK_FLAG_FRAME);
//	avcodec_flush_buffers(pCodecCtx);
//}

- (void)dealloc
{
   	// Free scaler
    sws_freeContext(img_convert_ctx);
    
    // Free RGB picture
    avpicture_free(&picture);
    
    // Free the packet that was allocated by av_read_frame
    av_free_packet(&packet);
    
    // Free the YUV frame
    av_free(pFrame);
    
    // Close the codec
    if (pCodecCtx) avcodec_close(pCodecCtx);
    
    // Close the video file
    if (pFormatCtx) avformat_close_input(&pFormatCtx);
    
    // Clode audio
    if (_audioCodecContext) avcodec_close(_audioCodecContext);
    if (_audioBuffer) av_free(_audioBuffer);
    
    [_audioController _stopAudio];
    
    _audioController = nil;
    audioPacketQueue = nil;
    audioPacketQueueLock = nil;
    
    NSLog(@"release");
}

- (BOOL) play
{
	// AVPacket packet;
    int frameFinished=0;
	@try {
	    while (!frameFinished && av_read_frame(pFormatCtx, &packet) >=0 ) {
	        
	        if (packet.stream_index==audioStream) {
                
	            [audioPacketQueueLock lock];
	            
	            audioPacketQueueSize += packet.size;
                
                NSData* data = [NSMutableData dataWithBytes:&packet length:sizeof(packet)];
	            [audioPacketQueue addObject:data];
                
	            [audioPacketQueueLock unlock];
	            
	            if (!primed) {
	                primed=YES;
	                [_audioController _startAudio];
	            }
                
	            if (emptyAudioBuffer) {
	                [_audioController enqueueBuffer:emptyAudioBuffer];
                }
	        }
		}
    }
    @catch (NSException *exception) {
        frameFinished = 0;
        NSLog(@"avcodec_decode_video2 %@", exception);
    }
	return frameFinished!=0;
}

- (void)setupAudioDecoder
{    
    if (audioStream >= 0) {
        _audioBufferSize = AVCODEC_MAX_AUDIO_FRAME_SIZE;
        _audioBuffer = av_malloc(_audioBufferSize);
        _inBuffer = NO;
        
        _audioCodecContext = pFormatCtx->streams[audioStream]->codec;
        _audioStream = pFormatCtx->streams[audioStream];
        
        AVCodec *codec = avcodec_find_decoder(_audioCodecContext->codec_id);
        if (codec == NULL) {
            NSLog(@"Not found audio codec.");
            return;
        }
        
        if (avcodec_open2(_audioCodecContext, codec, NULL) < 0) {
            NSLog(@"Could not open audio codec.");
            return;
        }
        
        if (audioPacketQueue) {
            audioPacketQueue = nil;
        }        
        audioPacketQueue = [[NSMutableArray alloc] init];
        
        if (audioPacketQueueLock) {
            audioPacketQueueLock = nil;
        }
        audioPacketQueueLock = [[NSLock alloc] init];
        
        if (_audioController) {
            [_audioController _stopAudio];
            _audioController = nil;
        }
        _audioController = [[AudioStreamer alloc] initWithStreamer:self];
    } else {
        pFormatCtx->streams[audioStream]->discard = AVDISCARD_ALL;
        audioStream = -1;
    }
}

- (AVPacket*)readPacket
{
    if (_currentPacket.size > 0 || _inBuffer)
        return &_currentPacket;
    
    NSMutableData *packetData = [audioPacketQueue objectAtIndex:0];
    _packet = [packetData mutableBytes];
    
    if (_packet->duration == 0) {
        lastPts = _packet->pts;
    }
    
    if (_packet) {
        if (_packet->dts != AV_NOPTS_VALUE) {
            _packet->dts += av_rescale_q(0, AV_TIME_BASE_Q, _audioStream->time_base);
        }
        
        if (_packet->pts != AV_NOPTS_VALUE) {
            _packet->pts += av_rescale_q(0, AV_TIME_BASE_Q, _audioStream->time_base);
        }
        
        [audioPacketQueueLock lock];
        audioPacketQueueSize -= _packet->size;
        if ([audioPacketQueue count] > 0) {
            [audioPacketQueue removeObjectAtIndex:0];
        }
        [audioPacketQueueLock unlock];
        
        _currentPacket = *(_packet);
    }
    
    printf("last: %lld, current: %lld duration: %d \n", lastPts, _packet->pts, _packet->duration);
    if (llabs(lastPts - _packet->pts) > _packet->duration * 2) {
        NSLog(@"Error !!! Try restart");
        audioPacketQueue = [NSMutableArray arrayWithObject:audioPacketQueue.lastObject];
    }
    
    lastPts = _packet->pts;
    
    return &_currentPacket;   
}

- (void)closeAudio
{
    [_audioController _stopAudio];
    primed=NO;
}

@end
