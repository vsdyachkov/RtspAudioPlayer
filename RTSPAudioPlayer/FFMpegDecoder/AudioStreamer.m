//



#import "AudioStreamer.h"
#import "RTSPPlayer.h"

@implementation AudioStreamer
{
    NSInteger state;
    NSLock* decodeLock;
    AudioStreamBasicDescription audioStreamBasicDesc;
    AudioQueueRef audioQueue;
    AudioQueueBufferRef audioQueueBuffer[kNumAQBufs];
    RTSPPlayer* streamer;
}

- (instancetype) initWithStreamer:(RTSPPlayer*)audioStreamer
{
    if (self = [super init])
    {
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
        streamer = audioStreamer;
        self.audioCodecContext = audioStreamer.audioCodecContext;
    }
    
    return  self;
}

- (void) startAudio
{

    state = AUDIO_STATE_READY;
    
    if (decodeLock) {
        [decodeLock unlock];
        decodeLock = nil;
    }
    
    decodeLock = [NSLock new];
    
    // CODEC_ID_AACC:
    audioStreamBasicDesc.mFormatID = kAudioFormatMPEG4AAC;
    audioStreamBasicDesc.mFormatFlags = kMPEG4Object_AAC_LC;
    audioStreamBasicDesc.mSampleRate = self.audioCodecContext->sample_rate;
    audioStreamBasicDesc.mChannelsPerFrame = self.audioCodecContext->channels;
    audioStreamBasicDesc.mBitsPerChannel = 0;
    audioStreamBasicDesc.mFramesPerPacket = self.audioCodecContext->frame_size;
    audioStreamBasicDesc.mBytesPerPacket = self.audioCodecContext->frame_bits;
    audioStreamBasicDesc.mBytesPerFrame = self.audioCodecContext->frame_bits;
    audioStreamBasicDesc.mReserved = 0;
    
    
    AudioQueueNewOutput(&audioStreamBasicDesc, audioQueueOutputCallback, (__bridge void*)self, NULL, NULL, 0, &audioQueue);
    AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, audioQueueIsRunningCallback, (__bridge void*)self);
    
    
    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
        AudioQueueAllocateBufferWithPacketDescriptions(audioQueue,
                                                       audioStreamBasicDesc.mSampleRate * kAudioBufferSeconds / 8,
                                                       self.audioCodecContext->sample_rate * kAudioBufferSeconds / (self.audioCodecContext->frame_size + 1),
                                                       &audioQueueBuffer[i]);
    }
    
    AudioQueueStart(audioQueue, NULL);

    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
      [self enqueueBuffer:audioQueueBuffer[i]];
    }

    state = AUDIO_STATE_PLAYING;
}

//- (void)removeAudioQueue
//{
//    AudioQueueStop(audioQueue, YES);
//    state = AUDIO_STATE_STOP;
//
//    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
//      AudioQueueFreeBuffer(audioQueue, audioQueueBuffer[i]);
//    }
//    
//    AudioQueueDispose(audioQueue, YES);
//    
//    if (decodeLock) {
//        [decodeLock unlock];
//        decodeLock = nil;
//    }
//}

// c header

void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    AudioStreamer *audioController = (__bridge AudioStreamer*)inClientData;
    [audioController audioQueueOutputCallback:inAQ inBuffer:inBuffer];
}

void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    AudioStreamer *audioController = (__bridge AudioStreamer*)inClientData;
    [audioController audioQueueIsRunningCallback];
}

// obj-c header

- (void)audioQueueOutputCallback:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer
{
    if (state == AUDIO_STATE_PLAYING) {
      [self enqueueBuffer:inBuffer];
    }
}

- (void)audioQueueIsRunningCallback
{
    UInt32 isRunning;
    UInt32 size = sizeof(isRunning);
    AudioQueueGetProperty(audioQueue, kAudioQueueProperty_IsRunning, &isRunning, &size);
}

- (void)enqueueBuffer:(AudioQueueBufferRef)buffer
{
    
    if (buffer) {
        AudioTimeStamp bufferStartTime;
        buffer->mAudioDataByteSize = 0;
        buffer->mPacketDescriptionCount = 0;
        
        if (streamer.audioPacketQueue.count <= 0) {
            streamer.emptyAudioBuffer = buffer;
            return;
        }

        streamer.emptyAudioBuffer = nil;
        
        while (streamer.audioPacketQueue.count && buffer->mPacketDescriptionCount < buffer->mPacketDescriptionCapacity) {
            AVPacket *packet = [streamer readPacket];
            
            if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= packet->size) {
                if (buffer->mPacketDescriptionCount == 0) {
                    bufferStartTime.mSampleTime = packet->dts * self.audioCodecContext->frame_size;
                    bufferStartTime.mFlags = kAudioTimeStampSampleTimeValid;
                }
                
                memcpy((uint8_t *)buffer->mAudioData + buffer->mAudioDataByteSize, packet->data, packet->size);
                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = packet->size;
                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = self.audioCodecContext->frame_size;
                
                buffer->mAudioDataByteSize += packet->size;
                buffer->mPacketDescriptionCount++;
                
                streamer.audioPacketQueueSize = packet->size;
                
                av_free_packet(packet);
            }
            else {
                break;
            }
        }
        
        [decodeLock lock];
        if (buffer->mPacketDescriptionCount > 0) {
            AudioQueueEnqueueBuffer(audioQueue, buffer, 0, NULL);
        } else {
            AudioQueueStop(audioQueue, NO);
        }
        [decodeLock unlock];
    }
    
    return;
}



@end
