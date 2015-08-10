//
//  RTSPPlayer.m
//  RtspStreamer
//
//  Created by Victor on 04.08.15.
//  Copyright (c) 2015 Company. All rights reserved.
//

#import "RTSPPlayer.h"
#import "avformat.h"
#import "avcodec.h"
#import "avio.h"
#import "swscale.h"
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#ifndef AVCODEC_MAX_AUDIO_FRAME_SIZE
# define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio
#endif

#define kNumAQBufs 3
#define kAudioBufferSeconds 3

typedef enum _AUDIO_STATE {
    AUDIO_STATE_READY           = 0,
    AUDIO_STATE_STOP            = 1,
    AUDIO_STATE_PLAYING         = 2,
    AUDIO_STATE_PAUSE           = 3,
    AUDIO_STATE_SEEKING         = 4
} AUDIO_STATE;


int state;
AudioQueueRef audioQueue;
AudioQueueBufferRef audioQueueBuffer[kNumAQBufs];
id selfClass;

@implementation RTSPPlayer
{
    int64_t lastPts;
    int16_t audioBuffer;
    int audioStreamNumber;
    
    NSMutableArray *audioPacketQueue;
    int audioPacketQueueSize;
    NSLock *audioPacketQueueLock;
    NSLock* decodeLock;
    
    AVPacket packet;
    AVPacket *_packet, _currentPacket;
    AVStream* audioStream;
    AVCodecContext* audioCodecContext;
    AVFormatContext *pFormatCtx;
    
    AudioQueueBufferRef emptyAudioBuffer;
    AudioStreamBasicDescription audioStreamBasicDesc;
}


- (id) initWithRtspAudioUrl:(NSString *)url
{
	if (!(self=[super init])) return nil;
    
    selfClass = self;
		
    // Register all formats and codecs
    avcodec_register_all();
    av_register_all();
    
    // Avformat network
    avformat_network_init();
    if (avformat_open_input(&pFormatCtx, [url UTF8String], NULL, 0) != 0)
    {
        NSLog(@"Connection failure, stream not started?");
        return nil;
    }
    
    // Get stream information
    avformat_find_stream_info(pFormatCtx, NULL);
    
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

- (void)dealloc
{
  
    AudioQueueStop(audioQueue, YES);
    state = AUDIO_STATE_STOP;
    
    // Free the packet that was allocated by av_read_frame
    av_free_packet(&packet);
    
    // Close the video file
    if (pFormatCtx) {
        pFormatCtx->streams[audioStreamNumber]->discard = AVDISCARD_ALL;
        audioStreamNumber = -1;
        avformat_close_input(&pFormatCtx);
    }
    
    // Clode audio
//    if (_audioCodecContext) avcodec_close(_audioCodecContext);
//    if (_audioBuffer) av_free(_audioBuffer);
    
    audioPacketQueue = nil;
    audioPacketQueueLock = nil;
    
    NSLog(@"Release");
}

- (void) play
{
    NSLog(@"Playing ...");
    
    while (av_read_frame(pFormatCtx, &packet) >= 0)
    {
        [audioPacketQueueLock lock];
        audioPacketQueueSize += packet.size;
        NSData* data = [NSMutableData dataWithBytes:&packet length:sizeof(packet)];
        [audioPacketQueue addObject:data];
        [audioPacketQueueLock unlock];

        if (emptyAudioBuffer) {
            [self enqueueBuffer:emptyAudioBuffer];
        }
    }

	return;
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
        [self startAudio];
    }
}

- (void) startAudio
{
    state = AUDIO_STATE_READY;
    
    // CODEC_ID_AACC:
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
        [self enqueueBuffer:audioQueueBuffer[i]];
    }
    
    state = AUDIO_STATE_PLAYING;
}


- (AVPacket*)readPacket
{
    if (_currentPacket.size > 0)
        return &_currentPacket;
    
    NSMutableData *packetData = [audioPacketQueue objectAtIndex:0];
    _packet = [packetData mutableBytes];
    
    if (_packet && _packet->duration == 0) {
        lastPts = _packet->pts;
    }
    
    if (_packet)
    {
        _packet->dts += av_rescale_q(0, AV_TIME_BASE_Q, audioStream->time_base);
        _packet->pts += av_rescale_q(0, AV_TIME_BASE_Q, audioStream->time_base);
        
        [audioPacketQueueLock lock];
        audioPacketQueueSize -= _packet->size;
        if ([audioPacketQueue count] > 0) {
            [audioPacketQueue removeObjectAtIndex:0];
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

// c header

void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    if (state == AUDIO_STATE_PLAYING) {
        [selfClass enqueueBuffer:inBuffer];
    }
}

void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    UInt32 isRunning;
    UInt32 size = sizeof(isRunning);
    if (AudioQueueGetProperty(audioQueue, kAudioQueueProperty_IsRunning, &isRunning, &size) != noErr) NSLog(@"AudioQueueGetProperty error");
}

- (void)enqueueBuffer:(AudioQueueBufferRef)buffer
{
    
    if (buffer) {
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
            
            if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= tempPacket->size) {
                if (buffer->mPacketDescriptionCount == 0) {
                    bufferStartTime.mSampleTime = tempPacket->dts * audioCodecContext->frame_size;
                    bufferStartTime.mFlags = kAudioTimeStampSampleTimeValid;
                }
                
                memcpy((uint8_t *)buffer->mAudioData + buffer->mAudioDataByteSize, tempPacket->data, tempPacket->size);
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
