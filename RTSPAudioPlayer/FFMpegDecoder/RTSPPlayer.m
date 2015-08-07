//



#import "RTSPPlayer.h"
#import "AudioStreamer.h"

#ifndef AVCODEC_MAX_AUDIO_FRAME_SIZE
# define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio
#endif

@implementation RTSPPlayer
{
    int64_t lastPts;
    int16_t *_audioBuffer;
    int audioStream;
    NSLock *audioPacketQueueLock;
    
    AudioStreamer *audioController;
    AVPacket packet;
    AVPacket *_packet, _currentPacket;
    AVStream *_audioStream;
    AVCodecContext *_audioCodecContext;
    AVFormatContext *pFormatCtx;
}


@synthesize _audioStream,_audioCodecContext;


- (id) initWithRtspAudioUrl:(NSString *)url
{
	if (!(self=[super init])) return nil;
		
    // Register all formats and codecs
    avcodec_register_all();
    av_register_all();
    
    // Avformat network
    avformat_network_init();
    avformat_open_input(&pFormatCtx, [url UTF8String], NULL, 0);
    
    // Get stream information
    avformat_find_stream_info(pFormatCtx, NULL);
    
    // Find the first audio stream
    audioStream = -1;

    for (int i=0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO) {
            audioStream=i;
        }
    }
    
    if (audioStream > -1) {
        [self setupAudioDecoder];
    }

	return self;
}

- (void)dealloc
{
    // Free the packet that was allocated by av_read_frame
    av_free_packet(&packet);
    
    // Close the video file
    if (pFormatCtx) avformat_close_input(&pFormatCtx);
    
    // Clode audio
//    if (_audioCodecContext) avcodec_close(_audioCodecContext);
//    if (_audioBuffer) av_free(_audioBuffer);
    
//    [_audioController _stopAudio];
    
    audioController = nil;
    self.audioPacketQueue = nil;
    audioPacketQueueLock = nil;
    
    NSLog(@"release");
}

- (void) play
{
    NSLog(@"Playing ...");
    
    while (av_read_frame(pFormatCtx, &packet) >=0 ) {
        
        if (packet.stream_index == audioStream) {
            
            [audioPacketQueueLock lock];
            self.audioPacketQueueSize += packet.size;
            NSData* data = [NSMutableData dataWithBytes:&packet length:sizeof(packet)];
            [self.audioPacketQueue addObject:data];
            [audioPacketQueueLock unlock];

            if (audioController != nil && self.emptyAudioBuffer) {
                [audioController enqueueBuffer:self.emptyAudioBuffer];
            }
        }
    }

	return;
}

- (void) setupAudioDecoder
{    
    if (audioStream >= 0) {
        _audioBuffer = av_malloc(AVCODEC_MAX_AUDIO_FRAME_SIZE);
        
        _audioCodecContext = pFormatCtx->streams[audioStream]->codec;
        _audioStream = pFormatCtx->streams[audioStream];
        
        AVCodec *codec = avcodec_find_decoder(_audioCodecContext->codec_id);
        avcodec_open2(_audioCodecContext, codec, NULL);
        
        self.audioPacketQueue = [NSMutableArray new];
        audioPacketQueueLock = [NSLock new];
        audioController = [[AudioStreamer alloc] initWithStreamer:self];
        [audioController startAudio];
    } else {
        pFormatCtx->streams[audioStream]->discard = AVDISCARD_ALL;
        audioStream = -1;
    }
}

- (AVPacket*)readPacket
{
    if (_currentPacket.size > 0)
        return &_currentPacket;
    
    NSMutableData *packetData = [self.audioPacketQueue objectAtIndex:0];
    _packet = [packetData mutableBytes];
    
    if (_packet && _packet->duration == 0) {
        lastPts = _packet->pts;
    }
    
    if (_packet)
    {
        _packet->dts += av_rescale_q(0, AV_TIME_BASE_Q, _audioStream->time_base);
        _packet->pts += av_rescale_q(0, AV_TIME_BASE_Q, _audioStream->time_base);
        
        [audioPacketQueueLock lock];
        self.audioPacketQueueSize -= _packet->size;
        if ([self.audioPacketQueue count] > 0) {
            [self.audioPacketQueue removeObjectAtIndex:0];
        }
        [audioPacketQueueLock unlock];
        
        _currentPacket = *(_packet);
    }
    
    if (_packet && llabs(lastPts - _packet->pts) > _packet->duration * 2)
    {
        NSLog(@"Disconnect found !!! Need restart");
        [[NSNotificationCenter defaultCenter] postNotificationName:@"restartStream" object:nil];
    }
    
    if (_packet) {
        lastPts = _packet->pts;
    }
    
    return &_currentPacket;   
}

@end
