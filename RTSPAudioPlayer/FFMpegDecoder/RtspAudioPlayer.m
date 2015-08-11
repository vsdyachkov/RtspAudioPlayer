//
//  RTSPPlayer.m
//  RtspStreamer
//
//  Created by Victor on 04.08.15.
//  Copyright (c) 2015 Company. All rights reserved.
//

#import "RtspAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "avformat.h"

#ifndef AVCODEC_MAX_AUDIO_FRAME_SIZE
# define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio
#endif

#define kNumAQBufs 1
#define kAudioBufferSeconds 8

typedef enum _AUDIO_STATE {
    AUDIO_STATE_READY   = 0,
    AUDIO_STATE_STOP    = 1,
    AUDIO_STATE_PLAYING = 2,
    AUDIO_STATE_PAUSE   = 3,
    AUDIO_STATE_SEEKING = 4
} AUDIO_STATE;

int state;
__weak id selfClass;
AudioQueueRef audioQueue;

@implementation RtspAudioPlayer
{
    int64_t lastPts;
    int audioStreamNumber;
    
    int16_t audioBuffer;
    NSMutableArray *audioPacketQueue;
    NSLock *audioPacketQueueLock;
    NSLock* decodeLock;
    int audioPacketQueueSize;
    
    AVPacket packet;
    AVPacket *_packet, currentPacket;
    AVStream* audioStream;
    AVCodecContext* audioCodecContext;
    AVFormatContext* pFormatCtx;
    
    AudioStreamBasicDescription audioStreamBasicDesc;
    AudioQueueBufferRef emptyAudioBuffer;
    AudioQueueBufferRef audioQueueBuffer[kNumAQBufs];
    
    BOOL stop;
}

- (void) dealloc
{
    NSLog(@"DEALLOC");
    
    
    // Free the packet that was allocated by av_read_frame
    av_free_packet(&packet);
    
    // Close the codec
    //if (pCodecCtx) avcodec_close(pCodecCtx);
    
    // Close the video file
    if (pFormatCtx) avformat_close_input(&pFormatCtx);
    
    AudioQueueRemovePropertyListener(audioQueue, kAudioQueueProperty_IsRunning, audioQueueIsRunningCallback, (__bridge void*)self);
    AudioQueueStop(audioQueue, YES);
    state = AUDIO_STATE_STOP;
    
    

    
    audioPacketQueue = nil;
    //audioPacketQueueLock = nil;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"restartStream" object:nil];
    NSLog(@"RELEASE");
}


- (id) initWithUrl:(NSString *)url
{
    if (!(self=[super init])) return nil;
    
    state = AUDIO_STATE_STOP;
    
    selfClass = self;
    
    // Register all the muxers, demuxers and protocols
    av_register_all();
    
    // Do global initialization of network components
    avformat_network_init();
    
    AVDictionary *opts = 0;
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    
    // Open an input stream and read the header
    if (avformat_open_input(&pFormatCtx, [url UTF8String], NULL, &opts) != 0)
    {
        NSLog(@"Connection failure, stream not started?");
        return nil;
    }
    
    // Get stream information
    if (avformat_find_stream_info(pFormatCtx, NULL) != 0) NSLog(@"avformat_find_stream_info");
    
    // Find the first audio stream
    audioStreamNumber = -1;
    
    for (int i=0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO) {
            audioStreamNumber=i;
        }
    }
    
    if (audioStreamNumber > -1) {
        [self setupAudioDecoder];
    }
    
    return self;
}

- (void) setupAudioDecoder
{
    if (audioStreamNumber >= 0)
    {
        audioBuffer = (int16_t)av_malloc(AVCODEC_MAX_AUDIO_FRAME_SIZE);
        
        audioCodecContext = pFormatCtx->streams[audioStreamNumber]->codec;
        audioStream = pFormatCtx->streams[audioStreamNumber];
        
        AVCodec *codec = avcodec_find_decoder(audioCodecContext->codec_id);
        avcodec_open2(audioCodecContext, codec, NULL);
        
        audioPacketQueue = [NSMutableArray new];
        audioPacketQueueLock = [NSLock new];
        decodeLock = [NSLock new];
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
        
        // Setup AAC audio codec
        
        audioStreamBasicDesc.mFormatID = kAudioFormatMPEG4AAC;
        audioStreamBasicDesc.mFormatFlags = kMPEG4Object_AAC_LC;
        audioStreamBasicDesc.mSampleRate = audioCodecContext->sample_rate;
        audioStreamBasicDesc.mChannelsPerFrame = audioCodecContext->channels;
        audioStreamBasicDesc.mBitsPerChannel = 0;
        audioStreamBasicDesc.mFramesPerPacket = audioCodecContext->frame_size;
        audioStreamBasicDesc.mBytesPerPacket = audioCodecContext->frame_bits;
        audioStreamBasicDesc.mBytesPerFrame = audioCodecContext->frame_bits;
        audioStreamBasicDesc.mReserved = 0;
        
        if (AudioQueueNewOutput(&audioStreamBasicDesc, audioQueueOutputCallback, (__bridge void*)self, NULL, NULL, 0, &audioQueue) != noErr) {
            NSLog(@"AudioQueueNewOutput error");
        }
        
        if (AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, audioQueueIsRunningCallback, (__bridge void*)self) != noErr) {
            NSLog(@"AudioQueueAddPropertyListener error");
        }
        
        for (NSInteger i = 0; i < kNumAQBufs; ++i) {
            if (AudioQueueAllocateBufferWithPacketDescriptions(audioQueue,
                                                               audioStreamBasicDesc.mSampleRate * kAudioBufferSeconds / 8,
                                                               audioCodecContext->sample_rate * kAudioBufferSeconds / (audioCodecContext->frame_size + 1),
                                                               &audioQueueBuffer[i]) != noErr) {
                NSLog(@"AudioQueueAllocateBufferWithPacketDescriptions error");
            }
        }
        
        if (AudioQueueStart(audioQueue, NULL) != noErr) NSLog(@"AudioQueueStart error");
        
        for (NSInteger i = 0; i < kNumAQBufs; ++i) {
            //NSLog(@" Before %d - %ld", audioQueueBuffer[i]->mAudioData == NULL, i);
            [self enqueueBuffer:audioQueueBuffer[i]];
            //NSLog(@" After %d - %ld", audioQueueBuffer[i]->mAudioData == NULL, i);
        }
        
        
        state = AUDIO_STATE_READY;
    }
}

- (void) play
{
    NSLog(@"Playing ...");
    //NSLog(@"BAD POINT %d", emptyAudioBuffer->mAudioData == NULL);
    
    state = AUDIO_STATE_PLAYING;
    
    while (state == AUDIO_STATE_PLAYING && av_read_frame(pFormatCtx, &packet) >= 0 && !stop)
    {
        [audioPacketQueueLock lock];
        audioPacketQueueSize += packet.size;
        NSData* data = [NSMutableData dataWithBytes:&packet length:sizeof(packet)];
        [audioPacketQueue addObject:data];
        [audioPacketQueueLock unlock];
        
        if (emptyAudioBuffer && state == AUDIO_STATE_PLAYING) {
            //NSLog(@"FINAL %d", emptyAudioBuffer->mAudioData == NULL);
            [self enqueueBuffer:emptyAudioBuffer];
        }
    }
    
    av_free_packet(&packet);
    
    return;
}

void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    //NSLog(@"Output");
    if (state == AUDIO_STATE_PLAYING) {
        [selfClass enqueueBuffer:inBuffer];
    }
}

void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    NSLog(@"QUEUE is RUNNING");
    UInt32 isRunning;
    UInt32 size = sizeof(isRunning);
    if (AudioQueueGetProperty(audioQueue, kAudioQueueProperty_IsRunning, &isRunning, &size) != noErr) NSLog(@"AudioQueueGetProperty error");
}

- (AVPacket*)readPacket
{
    //NSLog(@"Read Packet");
    if (currentPacket.size > 0)
        return &currentPacket;
    
    NSMutableData *packetData = [audioPacketQueue objectAtIndex:0];
    _packet = [packetData mutableBytes];
    
    if (_packet && _packet->duration == 0) {
        lastPts = _packet->pts;
    }
    
    if (_packet)
    {
        _packet->dts += av_rescale_q(0, AV_TIME_BASE_Q, audioStream->time_base);
        _packet->pts += av_rescale_q(0, AV_TIME_BASE_Q, audioStream->time_base);
        
//        NSLog(@"dts: %lld, pts: %lld", _packet->dts, _packet->pts);
        
        audioPacketQueueSize -= _packet->size;
        [audioPacketQueueLock lock];
        if ([audioPacketQueue count] > 0) {
            [audioPacketQueue removeObjectAtIndex:0];
        }
        [audioPacketQueueLock unlock];
        
        currentPacket = *(_packet);
    }
    
    if (_packet && llabs(lastPts - _packet->pts) > _packet->duration * 2)
    {
        NSLog(@"Missed more then 2 packets, need restart");
//        Disposes of an audio queue buffers
//        for (NSInteger i = 0; i < kNumAQBufs; ++i) {
//            AudioQueueFreeBuffer(audioQueue, audioQueueBuffer[i]);
//        }
//        audioPacketQueue = nil;
//        state = AUDIO_STATE_STOP;
        stop = YES;
        //[[NSNotificationCenter defaultCenter] postNotificationName:@"restartStream" object:nil];
    }
    
    if (_packet) {
        lastPts = _packet->pts;
    }
    
    return &currentPacket;
}

- (void)enqueueBuffer:(AudioQueueBufferRef)buffer
{
    
    if (buffer)
    {
        AudioTimeStamp bufferStartTime;
        buffer->mAudioDataByteSize = 0;
        buffer->mPacketDescriptionCount = 0;
        
        if (audioPacketQueue.count <= 0) {
            emptyAudioBuffer = buffer;
            return;
        }
        
        emptyAudioBuffer = nil;
        
        while (audioPacketQueue.count && buffer->mPacketDescriptionCount < buffer->mPacketDescriptionCapacity) {
            AVPacket *tempPacket = [self readPacket];
            if (state == AUDIO_STATE_STOP) {
                return;
            }
            
            if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= tempPacket->size) {
                if (buffer->mPacketDescriptionCount == 0) {
                    bufferStartTime.mSampleTime = tempPacket->dts * audioCodecContext->frame_size;
                    bufferStartTime.mFlags = kAudioTimeStampSampleTimeValid;
                }
                //NSLog(@"%d", buffer->mAudioData == NULL);
                memcpy(buffer->mAudioData + buffer->mAudioDataByteSize, tempPacket->data, tempPacket->size);
                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = tempPacket->size;
                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = audioCodecContext->frame_size;
                
                buffer->mAudioDataByteSize += tempPacket->size;
                buffer->mPacketDescriptionCount++;
                
                audioPacketQueueSize = tempPacket->size;
                
                av_free_packet(tempPacket);
            }
            else {
                break;
            }
        }
        
        [decodeLock lock];
        if (buffer->mPacketDescriptionCount > 0) {
            if (AudioQueueEnqueueBuffer(audioQueue, buffer, 0, NULL) != noErr) NSLog(@"AudioQueueEnqueueBuffer error");
        } else {
            if (AudioQueueStop(audioQueue, NO) != noErr) NSLog(@"AudioQueueStop error");
        }
        [decodeLock unlock];
    }
    
    return;
}

@end
