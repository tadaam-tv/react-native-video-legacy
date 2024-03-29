#import <React/RCTConvert.h>
#import "RCTVideo.h"
#import <React/RCTBridgeModule.h>
#import <React/RCTEventDispatcher.h>
#import <React/UIView+React.h>
#include <MediaAccessibility/MediaAccessibility.h>
#include <AVFoundation/AVFoundation.h>
#include <AVFoundation/AVAssetResourceLoader.h>
#import "UIKit/UIKit.h"

static NSString *const statusKeyPath = @"status";
static NSString *const playbackLikelyToKeepUpKeyPath = @"playbackLikelyToKeepUp";
static NSString *const playbackBufferEmptyKeyPath = @"playbackBufferEmpty";
static NSString *const readyForDisplayKeyPath = @"readyForDisplay";
static NSString *const playbackRate = @"rate";
static NSString *const timedMetadata = @"timedMetadata";

static int const RCTVideoUnset = -1;

@implementation RCTVideo
{
    AVPlayer *_player;
    AVPlayerItem *_playerItem;
    BOOL _playerItemObserversSet;
    BOOL _playerBufferEmpty;
    AVPlayerLayer *_playerLayer;
    BOOL _playerLayerObserverSet;
    AVPlayerViewController *_playerViewController;
    NSURL *_videoURL;
    
    /* Required to publish events */
    RCTEventDispatcher *_eventDispatcher;
    BOOL _playbackRateObserverRegistered;
    BOOL _videoLoadStarted;
    
    bool _pendingSeek;
    float _pendingSeekTime;
    float _lastSeekTime;
    
    /* For sending videoProgress events */
    Float64 _progressUpdateInterval;
    BOOL _controls;
    id _timeObserver;
    
    /* Keep track of any modifiers, need to be applied after each play */
    float _volume;
    float _rate;
    BOOL _muted;
    BOOL _paused;
    BOOL _repeat;
    BOOL _allowsExternalPlayback;
    NSArray * _textTracks;
    NSDictionary * _selectedTextTrack;
    NSDictionary * _selectedAudioTrack;
    BOOL _playbackStalled;
    BOOL _playInBackground;
    BOOL _playWhenInactive;
    NSString * _ignoreSilentSwitch;
    NSString * _resizeMode;
    BOOL _fullscreenPlayerPresented;
    UIViewController * _presentingViewController;
    
    NSData* _licenseServerCertificateData;
    NSString* _base64CertificateString;
    NSString* _customerId;
    NSString* _deviceId;
    NSString* _licenseUrl;
    NSString* _drmType;
    NSString* _authToken;
}

- (instancetype)initWithEventDispatcher:(RCTEventDispatcher *)eventDispatcher
{
    if ((self = [super init])) {
        _eventDispatcher = eventDispatcher;
        
        _playbackRateObserverRegistered = NO;
        _playbackStalled = NO;
        _rate = 1.0;
        _volume = 1.0;
        _resizeMode = @"AVLayerVideoGravityResizeAspectFill";
        _pendingSeek = false;
        _pendingSeekTime = 0.0f;
        _lastSeekTime = 0.0f;
        _progressUpdateInterval = 250;
        _controls = NO;
        _playerBufferEmpty = YES;
        _playInBackground = false;
        _allowsExternalPlayback = YES;
        _playWhenInactive = false;
        _ignoreSilentSwitch = @"ignore"; // inherit, ignore, obey.  Set to ignore as this is the default setting for apps where audio is part of the user experience (https://developer.apple.com/documentation/avfoundation/avaudiosessioncategory?language=objc)
        
        _licenseServerCertificateData = nil;
        _base64CertificateString = nil;
        _customerId = nil;
        _deviceId = nil;
        _licenseUrl = nil;
        _authToken = nil;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillResignActive:)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(audioRouteChanged:)
                                                     name:AVAudioSessionRouteChangeNotification
                                                   object:nil];

        // Start KeepAwake
        [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    }
    
    return self;
}

- (AVPlayerViewController*)createPlayerViewController:(AVPlayer*)player withPlayerItem:(AVPlayerItem*)playerItem {
    RCTVideoPlayerViewController* playerLayer= [[RCTVideoPlayerViewController alloc] init];
    playerLayer.showsPlaybackControls = YES;
    
    playerLayer.rctDelegate = self;
    playerLayer.view.frame = self.bounds;
    playerLayer.player = player;
    playerLayer.view.frame = self.bounds;
    
    return playerLayer;
}

/* ---------------------------------------------------------
 **  Get the duration for a AVPlayerItem.
 ** ------------------------------------------------------- */

- (CMTime)playerItemDuration
{
    AVPlayerItem *playerItem = [_player currentItem];
    if (playerItem.status == AVPlayerItemStatusReadyToPlay)
    {
        return([playerItem duration]);
    }
    
    return(kCMTimeInvalid);
}

- (CMTimeRange)playerItemSeekableTimeRange
{
    AVPlayerItem *playerItem = [_player currentItem];
    if (playerItem.status == AVPlayerItemStatusReadyToPlay)
    {
        return [playerItem seekableTimeRanges].firstObject.CMTimeRangeValue;
    }
    
    return (kCMTimeRangeZero);
}

-(void)addPlayerTimeObserver
{
    const Float64 progressUpdateIntervalMS = _progressUpdateInterval / 1000;
    // @see endScrubbing in AVPlayerDemoPlaybackViewController.m
    // of https://developer.apple.com/library/ios/samplecode/AVPlayerDemo/Introduction/Intro.html
    __weak RCTVideo *weakSelf = self;
    _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(progressUpdateIntervalMS, NSEC_PER_SEC)
                                                          queue:NULL
                                                     usingBlock:^(CMTime time) { [weakSelf sendProgressUpdate]; }
                     ];
}

/* Cancels the previously registered time observer. */
-(void)removePlayerTimeObserver
{
    if (_timeObserver)
    {
        [_player removeTimeObserver:_timeObserver];
        _timeObserver = nil;
    }
}

#pragma mark - Progress

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removePlayerLayer];
    [self removePlayerItemObservers];
    [_player removeObserver:self forKeyPath:playbackRate context:nil];
    [_player removeObserver:self forKeyPath:statusKeyPath context:nil];

    // Stop KeepAwake
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
}

#pragma mark - App lifecycle handlers

- (void)applicationWillResignActive:(NSNotification *)notification
{
    if (_playInBackground || _playWhenInactive || _paused) return;
    
    [_player pause];
    [_player setRate:0.0];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    if (_playInBackground) {
        // Needed to play sound in background. See https://developer.apple.com/library/ios/qa/qa1668/_index.html
        [_playerLayer setPlayer:nil];
    }
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self applyModifiers];
    if (_playInBackground) {
        [_playerLayer setPlayer:_player];
    }
}

#pragma mark - Audio events

- (void)audioRouteChanged:(NSNotification *)notification
{
    NSNumber *reason = [[notification userInfo] objectForKey:AVAudioSessionRouteChangeReasonKey];
    NSNumber *previousRoute = [[notification userInfo] objectForKey:AVAudioSessionRouteChangePreviousRouteKey];
    if (reason.unsignedIntValue == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        self.onVideoAudioBecomingNoisy(@{@"target": self.reactTag});
    }
}

#pragma mark - Progress

- (void)sendProgressUpdate
{
    AVPlayerItem *video = [_player currentItem];
    if (video == nil || video.status != AVPlayerItemStatusReadyToPlay) {
        return;
    }
    
    CMTime playerDuration = [self playerItemDuration];
    if (CMTIME_IS_INVALID(playerDuration)) {
        return;
    }
    
    CMTime currentTime = _player.currentTime;
    const Float64 duration = CMTimeGetSeconds(playerDuration);
    const Float64 currentTimeSecs = CMTimeGetSeconds(currentTime);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RCTVideo_progress" object:nil userInfo:@{@"progress": [NSNumber numberWithDouble: currentTimeSecs / duration]}];
    
    NSArray *logEvents = video.accessLog.events;
    AVPlayerItemAccessLogEvent *event = (AVPlayerItemAccessLogEvent *)[logEvents lastObject];
    // double observedBitrate=event.observedBitrate;
    double indicatedBitrate=event.indicatedBitrate;
    // double observedMinBitrate=event.observedMinBitrate;
    // double observedMaxBitrate=event.observedMaxBitrate;
    
    
    if( currentTimeSecs >= 0 && self.onVideoProgress) {
        self.onVideoProgress(@{
                               @"currentTime": [NSNumber numberWithFloat:CMTimeGetSeconds(currentTime)],
                               @"playableDuration": [self calculatePlayableDuration],
                               @"atValue": [NSNumber numberWithLongLong:currentTime.value],
                               @"atTimescale": [NSNumber numberWithInt:currentTime.timescale],
                               @"target": self.reactTag,
                               @"seekableDuration": [self calculateSeekableDuration],
                               // @"minThroughput": [NSNumber numberWithFloat:observedMinBitrate],
                               // @"maxThroughput": [NSNumber numberWithFloat:observedMaxBitrate],
                               // @"observedThroughput": [NSNumber numberWithFloat:observedBitrate],
                               @"streamBitRate": [NSNumber numberWithFloat:indicatedBitrate],
                               });
    }
}

/*!
 * Calculates and returns the playable duration of the current player item using its loaded time ranges.
 *
 * \returns The playable duration of the current player item in seconds.
 */
- (NSNumber *)calculatePlayableDuration
{
    AVPlayerItem *video = _player.currentItem;
    if (video.status == AVPlayerItemStatusReadyToPlay) {
        __block CMTimeRange effectiveTimeRange;
        [video.loadedTimeRanges enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            CMTimeRange timeRange = [obj CMTimeRangeValue];
            if (CMTimeRangeContainsTime(timeRange, video.currentTime)) {
                effectiveTimeRange = timeRange;
                *stop = YES;
            }
        }];
        Float64 playableDuration = CMTimeGetSeconds(CMTimeRangeGetEnd(effectiveTimeRange));
        if (playableDuration > 0) {
            return [NSNumber numberWithFloat:playableDuration];
        }
    }
    return [NSNumber numberWithInteger:0];
}

- (NSNumber *)calculateSeekableDuration
{
    CMTimeRange timeRange = [self playerItemSeekableTimeRange];
    if (CMTIME_IS_NUMERIC(timeRange.duration))
    {
        return [NSNumber numberWithFloat:CMTimeGetSeconds(timeRange.duration)];
    }
    return [NSNumber numberWithInteger:0];
}

- (void)addPlayerItemObservers
{
    [_playerItem addObserver:self forKeyPath:statusKeyPath options:0 context:nil];
    [_playerItem addObserver:self forKeyPath:playbackBufferEmptyKeyPath options:0 context:nil];
    [_playerItem addObserver:self forKeyPath:playbackLikelyToKeepUpKeyPath options:0 context:nil];
    [_playerItem addObserver:self forKeyPath:timedMetadata options:NSKeyValueObservingOptionNew context:nil];
    _playerItemObserversSet = YES;
}

/* Fixes https://github.com/brentvatne/react-native-video/issues/43
 * Crashes caused when trying to remove the observer when there is no
 * observer set */
- (void)removePlayerItemObservers
{
    if (_playerItemObserversSet) {
        [_playerItem removeObserver:self forKeyPath:statusKeyPath];
        [_playerItem removeObserver:self forKeyPath:playbackBufferEmptyKeyPath];
        [_playerItem removeObserver:self forKeyPath:playbackLikelyToKeepUpKeyPath];
        [_playerItem removeObserver:self forKeyPath:timedMetadata];
        _playerItemObserversSet = NO;
    }
}

#pragma mark - Player and source

- (void)setSrc:(NSDictionary *)source
{
    [self removePlayerLayer];
    [self removePlayerTimeObserver];
    [self removePlayerItemObservers];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

        // perform on next run loop, otherwise other passed react-props may not be set
        _playerItem = [self playerItemForSource:source];
        // _playerItem.preferredForwardBufferDuration = 0; // 5 sec buffering
        [self addPlayerItemObservers];
        
        [_player pause];
        [_playerViewController.view removeFromSuperview];
        _playerViewController = nil;
        
        if (_playbackRateObserverRegistered) {
            [_player removeObserver:self forKeyPath:playbackRate context:nil];
            [_player removeObserver:self forKeyPath:statusKeyPath context:nil];
            _playbackRateObserverRegistered = NO;
        }
        
        _player = [AVPlayer playerWithPlayerItem:_playerItem];
        _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        
        [_player addObserver:self forKeyPath:playbackRate options:0 context:nil];
        [_player addObserver:self forKeyPath:statusKeyPath options:0 context:nil];
        _playbackRateObserverRegistered = YES;
        
        [self addPlayerTimeObserver];
        
        //Perform on next run loop, otherwise onVideoLoadStart is nil
        if(self.onVideoLoadStart) {
            id uri = [source objectForKey:@"uri"];
            id type = [source objectForKey:@"type"];
            self.onVideoLoadStart(@{@"src": @{
                                            @"uri": uri ? uri : [NSNull null],
                                            @"type": type ? type : [NSNull null],
                                            @"isNetwork": [NSNumber numberWithBool:(bool)[source objectForKey:@"isNetwork"]]},
                                    @"target": self.reactTag
                                    });
        }
        
    });
    _videoLoadStarted = YES;
}

- (NSURL*) urlFilePath:(NSString*) filepath {
    if ([filepath containsString:@"file://"]) {
        return [NSURL URLWithString:filepath];
    }
    
    // code to support local caching
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* relativeFilePath = [filepath lastPathComponent];
    // the file may be multiple levels below the documents directory
    NSArray* fileComponents = [filepath componentsSeparatedByString:@"Documents/"];
    if (fileComponents.count>1) {
        relativeFilePath = [fileComponents objectAtIndex:1];
    }
    
    NSString *path = [paths.firstObject stringByAppendingPathComponent:relativeFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return [NSURL fileURLWithPath:path];
    }
    return nil;
}

- (AVPlayerItem*)playerItemForSource:(NSDictionary *)source
{
    bool isNetwork = [RCTConvert BOOL:[source objectForKey:@"isNetwork"]];
    bool isAsset = [RCTConvert BOOL:[source objectForKey:@"isAsset"]];
    NSString *uri = [source objectForKey:@"uri"];
    NSString *type = [source objectForKey:@"type"];
    
    AVURLAsset *asset;
    NSMutableDictionary *assetOptions = [[NSMutableDictionary alloc] init];
    
    if (isNetwork) {
        /* Per #1091, this is not a public API. We need to either get approval from Apple to use this
         * or use a different approach.
         NSDictionary *headers = [source objectForKey:@"requestHeaders"];
         if ([headers count] > 0) {
         [assetOptions setObject:headers forKey:@"AVURLAssetHTTPHeaderFieldsKey"];
         }
         */
        NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];
        [assetOptions setObject:cookies forKey:AVURLAssetHTTPCookiesKey];
        asset = [AVURLAsset URLAssetWithURL:[NSURL URLWithString:uri] options:assetOptions];
        
        // add Fairplay DRM
        dispatch_queue_t fairPlayQueue = dispatch_queue_create("FairplayQueue", NULL);
        [asset.resourceLoader setDelegate:self queue:fairPlayQueue];
        
    } else if (isAsset) { //  assets on iOS can be in the Bundle or Documents folder
        asset = [AVURLAsset URLAssetWithURL:[self urlFilePath:uri] options:nil];
    } else { // file passed in through JS, or an asset in the Xcode project
        asset = [AVURLAsset URLAssetWithURL:[[NSURL alloc] initFileURLWithPath:[[NSBundle mainBundle] pathForResource:uri ofType:type]] options:nil];
    }
    
    if (!_textTracks) {
        return [AVPlayerItem playerItemWithAsset:asset];
    }
    
    // sideload text tracks
    AVMutableComposition *mixComposition = [[AVMutableComposition alloc] init];
    
    AVAssetTrack *videoAsset = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVMutableCompositionTrack *videoCompTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    [videoCompTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.timeRange.duration)
                            ofTrack:videoAsset
                             atTime:kCMTimeZero
                              error:nil];
    
    AVAssetTrack *audioAsset = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    AVMutableCompositionTrack *audioCompTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    [audioCompTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.timeRange.duration)
                            ofTrack:audioAsset
                             atTime:kCMTimeZero
                              error:nil];
    
    NSMutableArray* validTextTracks = [NSMutableArray array];
    for (int i = 0; i < _textTracks.count; ++i) {
        AVURLAsset *textURLAsset;
        NSString *textUri = [_textTracks objectAtIndex:i][@"uri"];
        if ([[textUri lowercaseString] hasPrefix:@"http"]) {
            textURLAsset = [AVURLAsset URLAssetWithURL:[NSURL URLWithString:textUri] options:assetOptions];
        } else {
            textURLAsset = [AVURLAsset URLAssetWithURL:[self urlFilePath:textUri] options:nil];
        }
        AVAssetTrack *textTrackAsset = [textURLAsset tracksWithMediaType:AVMediaTypeText].firstObject;
        if (!textTrackAsset) continue; // fix when there's no textTrackAsset
        [validTextTracks addObject:[_textTracks objectAtIndex:i]];
        AVMutableCompositionTrack *textCompTrack = [mixComposition
                                                    addMutableTrackWithMediaType:AVMediaTypeText
                                                    preferredTrackID:kCMPersistentTrackID_Invalid];
        [textCompTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.timeRange.duration)
                               ofTrack:textTrackAsset
                                atTime:kCMTimeZero
                                 error:nil];
    }
    if (validTextTracks.count != _textTracks.count) {
        [self setTextTracks:validTextTracks];
    }
    
    return [AVPlayerItem playerItemWithAsset:mixComposition];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == _playerItem) {
        // When timeMetadata is read the event onTimedMetadata is triggered
        if ([keyPath isEqualToString:timedMetadata]) {
            NSArray<AVMetadataItem *> *items = [change objectForKey:@"new"];
            if (items && ![items isEqual:[NSNull null]] && items.count > 0) {
                NSMutableArray *array = [NSMutableArray new];
                for (AVMetadataItem *item in items) {
                    NSString *value = (NSString *)item.value;
                    NSString *identifier = item.identifier;
                    
                    if (![value isEqual: [NSNull null]]) {
                        NSDictionary *dictionary = [[NSDictionary alloc] initWithObjects:@[value, identifier] forKeys:@[@"value", @"identifier"]];
                        
                        [array addObject:dictionary];
                    }
                }
                
                self.onTimedMetadata(@{
                                       @"target": self.reactTag,
                                       @"metadata": array
                                       });
            }
        }
        
        if ([keyPath isEqualToString:statusKeyPath]) {
            // Handle player item status change.
            if (_playerItem.status == AVPlayerItemStatusReadyToPlay) {
                float duration = CMTimeGetSeconds(_playerItem.asset.duration);
                
                if (isnan(duration)) {
                    duration = 0.0;
                }
                
                NSObject *width = @"undefined";
                NSObject *height = @"undefined";
                NSString *orientation = @"undefined";
                
                if ([_playerItem.asset tracksWithMediaType:AVMediaTypeVideo].count > 0) {
                    AVAssetTrack *videoTrack = [[_playerItem.asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
                    width = [NSNumber numberWithFloat:videoTrack.naturalSize.width];
                    height = [NSNumber numberWithFloat:videoTrack.naturalSize.height];
                    CGAffineTransform preferredTransform = [videoTrack preferredTransform];
                    
                    if ((videoTrack.naturalSize.width == preferredTransform.tx
                         && videoTrack.naturalSize.height == preferredTransform.ty)
                        || (preferredTransform.tx == 0 && preferredTransform.ty == 0))
                    {
                        orientation = @"landscape";
                    } else {
                        orientation = @"portrait";
                    }
                }
                
                if (self.onVideoLoad && _videoLoadStarted) {
                    self.onVideoLoad(@{@"duration": [NSNumber numberWithFloat:duration],
                                       @"currentTime": [NSNumber numberWithFloat:CMTimeGetSeconds(_playerItem.currentTime)],
                                       @"canPlayReverse": [NSNumber numberWithBool:_playerItem.canPlayReverse],
                                       @"canPlayFastForward": [NSNumber numberWithBool:_playerItem.canPlayFastForward],
                                       @"canPlaySlowForward": [NSNumber numberWithBool:_playerItem.canPlaySlowForward],
                                       @"canPlaySlowReverse": [NSNumber numberWithBool:_playerItem.canPlaySlowReverse],
                                       @"canStepBackward": [NSNumber numberWithBool:_playerItem.canStepBackward],
                                       @"canStepForward": [NSNumber numberWithBool:_playerItem.canStepForward],
                                       @"naturalSize": @{
                                               @"width": width,
                                               @"height": height,
                                               @"orientation": orientation
                                               },
                                       @"audioTracks": [self getAudioTrackInfo],
                                       @"textTracks": [self getTextTrackInfo],
                                       @"target": self.reactTag});
                }
                _videoLoadStarted = NO;
                
                [self attachListeners];
                [self applyModifiers];
            } else if (_playerItem.status == AVPlayerItemStatusFailed && self.onVideoError) {
                NSString *errorTitle = [NSString stringWithFormat:@"%ld: %@", (long)_playerItem.error.code, _playerItem.error.domain];
                self.onVideoError(@{@"error": @{@"title": errorTitle, @"message": _playerItem.error.localizedDescription},
                                    @"target": self.reactTag});
                NSLog(@"onVideoError: PlayerItem status 'Failed' with error code: %ld", _playerItem.error.code);
                NSLog(@"onVideoError: PlayerItem status 'Failed' with error domain: %@", _playerItem.error.domain);
                NSLog(@"onVideoError: PlayerItem status 'Failed' with localizedDescription: %@", _playerItem.error.localizedDescription);
            }
        } else if ([keyPath isEqualToString:playbackBufferEmptyKeyPath]) {
            _playerBufferEmpty = YES;
            self.onVideoBuffer(@{@"isBuffering": @(YES), @"target": self.reactTag});
        } else if ([keyPath isEqualToString:playbackLikelyToKeepUpKeyPath]) {
            // Continue playing (or not if paused) after being paused due to hitting an unbuffered zone.
            if ((!(_controls || _fullscreenPlayerPresented) || _playerBufferEmpty) && _playerItem.playbackLikelyToKeepUp) {
                [self setPaused:_paused];
            }
            _playerBufferEmpty = NO;
            self.onVideoBuffer(@{@"isBuffering": @(NO), @"target": self.reactTag});
        }
    } else if (object == _playerLayer) {
        if([keyPath isEqualToString:readyForDisplayKeyPath] && [change objectForKey:NSKeyValueChangeNewKey]) {
            if([change objectForKey:NSKeyValueChangeNewKey] && self.onReadyForDisplay) {
                self.onReadyForDisplay(@{@"target": self.reactTag});
            }
        }
    } else if (object == _player) {
        if([keyPath isEqualToString:playbackRate]) {
            if(self.onPlaybackRateChange) {
                self.onPlaybackRateChange(@{@"playbackRate": [NSNumber numberWithFloat:_player.rate],
                                            @"target": self.reactTag});
            }
            if(_playbackStalled && _player.rate > 0) {
                if(self.onPlaybackResume) {
                    self.onPlaybackResume(@{@"playbackRate": [NSNumber numberWithFloat:_player.rate],
                                            @"target": self.reactTag});
                }
                _playbackStalled = NO;
            }
        }
        if ([keyPath isEqualToString:statusKeyPath]) {
            if (_player.status == AVPlayerStatusFailed) {
                NSLog(@"WILLIAM: AVPlayer status 'failed' with error: %lf", _player.error.code);
            }
            //else if (_player.status == AVPlayerStatusReadyToPlay) {
            //    NSLog(@"WILLIAM: AVPlayer status 'readyToPlay'");
            //}
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)attachListeners
{
    // listen for end of file
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:[_player currentItem]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:[_player currentItem]];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemPlaybackStalledNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playbackStalled:)
                                                 name:AVPlayerItemPlaybackStalledNotification
                                               object:nil];
}

- (void)playbackStalled:(NSNotification *)notification
{
    if(self.onPlaybackStalled) {
        self.onPlaybackStalled(@{@"target": self.reactTag});
    }
    _playbackStalled = YES;
}

- (void)playerItemDidReachEnd:(NSNotification *)notification
{
    if(self.onVideoEnd) {
        self.onVideoEnd(@{@"target": self.reactTag});
    }
    
    if (_repeat) {
        AVPlayerItem *item = [notification object];
        [item seekToTime:kCMTimeZero];
        [self applyModifiers];
    } else {
        [self removePlayerTimeObserver];
    }
}

#pragma mark - Prop setters

- (void)setResizeMode:(NSString*)mode
{
    if( _controls )
    {
        _playerViewController.videoGravity = mode;
    }
    else
    {
        _playerLayer.videoGravity = mode;
    }
    _resizeMode = mode;
}

- (void)setPlayInBackground:(BOOL)playInBackground
{
    _playInBackground = playInBackground;
}

- (void)setAllowsExternalPlayback:(BOOL)allowsExternalPlayback
{
    _allowsExternalPlayback = allowsExternalPlayback;
    _player.allowsExternalPlayback = _allowsExternalPlayback;
}

- (void)setPlayWhenInactive:(BOOL)playWhenInactive
{
    _playWhenInactive = playWhenInactive;
}

- (void)setIgnoreSilentSwitch:(NSString *)ignoreSilentSwitch
{
    _ignoreSilentSwitch = ignoreSilentSwitch;
    [self applyModifiers];
}

- (void)setPaused:(BOOL)paused
{
    if (paused) {
        [_player pause];
        [_player setRate:0.0];
    } else {
        if([_ignoreSilentSwitch isEqualToString:@"ignore"]) {
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        } else if([_ignoreSilentSwitch isEqualToString:@"obey"]) {
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
        }
        [_player play];
        [_player setRate:_rate];
    }
    
    _paused = paused;
}

- (float)getCurrentTime
{
    return _playerItem != NULL ? CMTimeGetSeconds(_playerItem.currentTime) : 0;
}

- (void)setCurrentTime:(float)currentTime
{
    NSDictionary *info = @{
                           @"time": [NSNumber numberWithFloat:currentTime],
                           @"tolerance": [NSNumber numberWithInt:100]
                           };
    [self setSeek:info];
}

- (void)setSeek:(NSDictionary *)info
{
    NSNumber *seekTime = info[@"time"];
    NSNumber *seekTolerance = info[@"tolerance"];
    
    int timeScale = 1000;
    
    AVPlayerItem *item = _player.currentItem;
    if (item && item.status == AVPlayerItemStatusReadyToPlay) {
        // TODO check loadedTimeRanges
        
        CMTime cmSeekTime = CMTimeMakeWithSeconds([seekTime floatValue], timeScale);
        CMTime current = item.currentTime;
        // TODO figure out a good tolerance level
        CMTime tolerance = CMTimeMake([seekTolerance floatValue], timeScale);
        BOOL wasPaused = _paused;
        
        if (CMTimeCompare(current, cmSeekTime) != 0) {
            if (!wasPaused) [_player pause];
            [_player seekToTime:cmSeekTime toleranceBefore:tolerance toleranceAfter:tolerance completionHandler:^(BOOL finished) {
                if (!_timeObserver) {
                    [self addPlayerTimeObserver];
                }
                if (!wasPaused) {
                    [self setPaused:false];
                }
                if(self.onVideoSeek) {
                    self.onVideoSeek(@{@"currentTime": [NSNumber numberWithFloat:CMTimeGetSeconds(item.currentTime)],
                                       @"seekTime": seekTime,
                                       @"target": self.reactTag});
                }
            }];
            
            _pendingSeek = false;
        }
        
    } else {
        // TODO: See if this makes sense and if so, actually implement it
        _pendingSeek = true;
        _pendingSeekTime = [seekTime floatValue];
    }
}

- (void)setRate:(float)rate
{
    _rate = rate;
    [self applyModifiers];
}

- (void)setMuted:(BOOL)muted
{
    _muted = muted;
    [self applyModifiers];
}

- (void)setVolume:(float)volume
{
    _volume = volume;
    [self applyModifiers];
}

- (void)applyModifiers
{
    if (_muted) {
        [_player setVolume:0];
        [_player setMuted:YES];
    } else {
        [_player setVolume:_volume];
        [_player setMuted:NO];
    }
    
    [self setSelectedAudioTrack:_selectedAudioTrack];
    [self setSelectedTextTrack:_selectedTextTrack];
    [self setResizeMode:_resizeMode];
    [self setRepeat:_repeat];
    [self setPaused:_paused];
    [self setControls:_controls];
    [self setAllowsExternalPlayback:_allowsExternalPlayback];
}

- (void)setRepeat:(BOOL)repeat {
    _repeat = repeat;
}

- (void)setMediaSelectionTrackForCharacteristic:(AVMediaCharacteristic)characteristic
                                   withCriteria:(NSDictionary *)criteria
{
    NSString *type = criteria[@"type"];
    AVMediaSelectionGroup *group = [_player.currentItem.asset
                                    mediaSelectionGroupForMediaCharacteristic:characteristic];
    AVMediaSelectionOption *mediaOption;
    
    if ([type isEqualToString:@"disabled"]) {
        // Do nothing. We want to ensure option is nil
    } else if ([type isEqualToString:@"language"] || [type isEqualToString:@"title"]) {
        NSString *value = criteria[@"value"];
        for (int i = 0; i < group.options.count; ++i) {
            AVMediaSelectionOption *currentOption = [group.options objectAtIndex:i];
            NSString *optionValue;
            if ([type isEqualToString:@"language"]) {
                optionValue = [currentOption extendedLanguageTag];
            } else {
                optionValue = [[[currentOption commonMetadata]
                                valueForKey:@"value"]
                               objectAtIndex:0];
            }
            if ([value isEqualToString:optionValue]) {
                mediaOption = currentOption;
                break;
            }
        }
        //} else if ([type isEqualToString:@"default"]) {
        //  option = group.defaultOption; */
    } else if ([type isEqualToString:@"index"]) {
        if ([criteria[@"value"] isKindOfClass:[NSNumber class]]) {
            int index = [criteria[@"value"] intValue];
            if (group.options.count > index) {
                mediaOption = [group.options objectAtIndex:index];
            }
        }
    } else { // default. invalid type or "system"
        [_player.currentItem selectMediaOptionAutomaticallyInMediaSelectionGroup:group];
        return;
    }
    
    // If a match isn't found, option will be nil and text tracks will be disabled
    [_player.currentItem selectMediaOption:mediaOption inMediaSelectionGroup:group];
}

- (void)setSelectedAudioTrack:(NSDictionary *)selectedAudioTrack {
    _selectedAudioTrack = selectedAudioTrack;
    [self setMediaSelectionTrackForCharacteristic:AVMediaCharacteristicAudible
                                     withCriteria:_selectedAudioTrack];
}

- (void)setSelectedTextTrack:(NSDictionary *)selectedTextTrack {
    _selectedTextTrack = selectedTextTrack;
    if (_textTracks) { // sideloaded text tracks
        [self setSideloadedText];
    } else { // text tracks included in the HLS playlist
        [self setMediaSelectionTrackForCharacteristic:AVMediaCharacteristicLegible
                                         withCriteria:_selectedTextTrack];
    }
}

- (void) setSideloadedText {
    NSString *type = _selectedTextTrack[@"type"];
    NSArray *textTracks = [self getTextTrackInfo];
    
    // The first few tracks will be audio & video track
    int firstTextIndex = 0;
    for (firstTextIndex = 0; firstTextIndex < _player.currentItem.tracks.count; ++firstTextIndex) {
        if ([_player.currentItem.tracks[firstTextIndex].assetTrack hasMediaCharacteristic:AVMediaCharacteristicLegible]) {
            break;
        }
    }
    
    int selectedTrackIndex = RCTVideoUnset;
    
    if ([type isEqualToString:@"disabled"]) {
        // Do nothing. We want to ensure option is nil
    } else if ([type isEqualToString:@"language"]) {
        NSString *selectedValue = _selectedTextTrack[@"value"];
        for (int i = 0; i < textTracks.count; ++i) {
            NSDictionary *currentTextTrack = [textTracks objectAtIndex:i];
            if ([selectedValue isEqualToString:currentTextTrack[@"language"]]) {
                selectedTrackIndex = i;
                break;
            }
        }
    } else if ([type isEqualToString:@"title"]) {
        NSString *selectedValue = _selectedTextTrack[@"value"];
        for (int i = 0; i < textTracks.count; ++i) {
            NSDictionary *currentTextTrack = [textTracks objectAtIndex:i];
            if ([selectedValue isEqualToString:currentTextTrack[@"title"]]) {
                selectedTrackIndex = i;
                break;
            }
        }
    } else if ([type isEqualToString:@"index"]) {
        if ([_selectedTextTrack[@"value"] isKindOfClass:[NSNumber class]]) {
            int index = [_selectedTextTrack[@"value"] intValue];
            if (textTracks.count > index) {
                selectedTrackIndex = index;
            }
        }
    }
    
    // in the situation that a selected text track is not available (eg. specifies a textTrack not available)
    if (![type isEqualToString:@"disabled"] && selectedTrackIndex == RCTVideoUnset) {
        CFArrayRef captioningMediaCharacteristics = MACaptionAppearanceCopyPreferredCaptioningMediaCharacteristics(kMACaptionAppearanceDomainUser);
        NSArray *captionSettings = (__bridge NSArray*)captioningMediaCharacteristics;
        if ([captionSettings containsObject:AVMediaCharacteristicTranscribesSpokenDialogForAccessibility]) {
            selectedTrackIndex = 0; // If we can't find a match, use the first available track
            NSString *systemLanguage = [[NSLocale preferredLanguages] firstObject];
            for (int i = 0; i < textTracks.count; ++i) {
                NSDictionary *currentTextTrack = [textTracks objectAtIndex:i];
                if ([systemLanguage isEqualToString:currentTextTrack[@"language"]]) {
                    selectedTrackIndex = i;
                    break;
                }
            }
        }
    }
    
    for (int i = firstTextIndex; i < _player.currentItem.tracks.count; ++i) {
        BOOL isEnabled = NO;
        if (selectedTrackIndex != RCTVideoUnset) {
            isEnabled = i == selectedTrackIndex + firstTextIndex;
        }
        [_player.currentItem.tracks[i] setEnabled:isEnabled];
    }
}

-(void) setStreamingText {
    NSString *type = _selectedTextTrack[@"type"];
    AVMediaSelectionGroup *group = [_player.currentItem.asset
                                    mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicLegible];
    AVMediaSelectionOption *mediaOption;
    
    if ([type isEqualToString:@"disabled"]) {
        // Do nothing. We want to ensure option is nil
    } else if ([type isEqualToString:@"language"] || [type isEqualToString:@"title"]) {
        NSString *value = _selectedTextTrack[@"value"];
        for (int i = 0; i < group.options.count; ++i) {
            AVMediaSelectionOption *currentOption = [group.options objectAtIndex:i];
            NSString *optionValue;
            if ([type isEqualToString:@"language"]) {
                optionValue = [currentOption extendedLanguageTag];
            } else {
                optionValue = [[[currentOption commonMetadata]
                                valueForKey:@"value"]
                               objectAtIndex:0];
            }
            if ([value isEqualToString:optionValue]) {
                mediaOption = currentOption;
                break;
            }
        }
        //} else if ([type isEqualToString:@"default"]) {
        //  option = group.defaultOption; */
    } else if ([type isEqualToString:@"index"]) {
        if ([_selectedTextTrack[@"value"] isKindOfClass:[NSNumber class]]) {
            int index = [_selectedTextTrack[@"value"] intValue];
            if (group.options.count > index) {
                mediaOption = [group.options objectAtIndex:index];
            }
        }
    } else { // default. invalid type or "system"
        [_player.currentItem selectMediaOptionAutomaticallyInMediaSelectionGroup:group];
        return;
    }
    
    // If a match isn't found, option will be nil and text tracks will be disabled
    [_player.currentItem selectMediaOption:mediaOption inMediaSelectionGroup:group];
}

- (void)setTextTracks:(NSArray*) textTracks;
{
    _textTracks = textTracks;
    
    // in case textTracks was set after selectedTextTrack
    if (_selectedTextTrack) [self setSelectedTextTrack:_selectedTextTrack];
}

- (NSArray *)getAudioTrackInfo
{
    NSMutableArray *audioTracks = [[NSMutableArray alloc] init];
    AVMediaSelectionGroup *group = [_player.currentItem.asset
                                    mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible];
    for (int i = 0; i < group.options.count; ++i) {
        AVMediaSelectionOption *currentOption = [group.options objectAtIndex:i];
        NSString *title = @"";
        NSArray *values = [[currentOption commonMetadata] valueForKey:@"value"];
        if (values.count > 0) {
            title = [values objectAtIndex:0];
        }
        NSString *language = [currentOption extendedLanguageTag] ? [currentOption extendedLanguageTag] : @"";
        NSDictionary *audioTrack = @{
                                     @"index": [NSNumber numberWithInt:i],
                                     @"title": title,
                                     @"language": language
                                     };
        [audioTracks addObject:audioTrack];
    }
    return audioTracks;
}

- (NSArray *)getTextTrackInfo
{
    // if sideloaded, textTracks will already be set
    if (_textTracks) return _textTracks;
    
    // if streaming video, we extract the text tracks
    NSMutableArray *textTracks = [[NSMutableArray alloc] init];
    AVMediaSelectionGroup *group = [_player.currentItem.asset
                                    mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicLegible];
    for (int i = 0; i < group.options.count; ++i) {
        AVMediaSelectionOption *currentOption = [group.options objectAtIndex:i];
        NSString *title = @"";
        NSArray *values = [[currentOption commonMetadata] valueForKey:@"value"];
        if (values.count > 0) {
            title = [values objectAtIndex:0];
        }
        NSString *language = [currentOption extendedLanguageTag] ? [currentOption extendedLanguageTag] : @"";
        NSDictionary *textTrack = @{
                                    @"index": [NSNumber numberWithInt:i],
                                    @"title": title,
                                    @"language": language
                                    };
        [textTracks addObject:textTrack];
    }
    return textTracks;
}

- (BOOL)getFullscreen
{
    return _fullscreenPlayerPresented;
}

- (void)setFullscreen:(BOOL)fullscreen
{
    if( fullscreen && !_fullscreenPlayerPresented )
    {
        // Ensure player view controller is not null
        if( !_playerViewController )
        {
            [self usePlayerViewController];
        }
        // Set presentation style to fullscreen
        [_playerViewController setModalPresentationStyle:UIModalPresentationFullScreen];
        
        // Find the nearest view controller
        UIViewController *viewController = [self firstAvailableUIViewController];
        if( !viewController )
        {
            UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
            viewController = keyWindow.rootViewController;
            if( viewController.childViewControllers.count > 0 )
            {
                viewController = viewController.childViewControllers.lastObject;
            }
        }
        if( viewController )
        {
            _presentingViewController = viewController;
            if(self.onVideoFullscreenPlayerWillPresent) {
                self.onVideoFullscreenPlayerWillPresent(@{@"target": self.reactTag});
            }
            [viewController presentViewController:_playerViewController animated:true completion:^{
                _playerViewController.showsPlaybackControls = YES;
                _fullscreenPlayerPresented = fullscreen;
                if(self.onVideoFullscreenPlayerDidPresent) {
                    self.onVideoFullscreenPlayerDidPresent(@{@"target": self.reactTag});
                }
            }];
        }
    }
    else if ( !fullscreen && _fullscreenPlayerPresented )
    {
        [self videoPlayerViewControllerWillDismiss:_playerViewController];
        [_presentingViewController dismissViewControllerAnimated:true completion:^{
            [self videoPlayerViewControllerDidDismiss:_playerViewController];
        }];
    }
}

- (void)usePlayerViewController
{
    if( _player )
    {
        _playerViewController = [self createPlayerViewController:_player withPlayerItem:_playerItem];
        // to prevent video from being animated when resizeMode is 'cover'
        // resize mode must be set before subview is added
        [self setResizeMode:_resizeMode];
        [self addSubview:_playerViewController.view];
    }
}

- (void)usePlayerLayer
{
    if( _player )
    {
        _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
        _playerLayer.frame = self.bounds;
        _playerLayer.needsDisplayOnBoundsChange = YES;
                
        // to prevent video from being animated when resizeMode is 'cover'
        // resize mode must be set before layer is added
        [self setResizeMode:_resizeMode];
        [_playerLayer addObserver:self forKeyPath:readyForDisplayKeyPath options:NSKeyValueObservingOptionNew context:nil];
        _playerLayerObserverSet = YES;
        
        [self.layer addSublayer:_playerLayer];
        self.layer.needsDisplayOnBoundsChange = YES;
    }
}

- (void)setControls:(BOOL)controls
{
    if( _controls != controls || (!_playerLayer && !_playerViewController) )
    {
        _controls = controls;
        if( _controls )
        {
            [self removePlayerLayer];
            [self usePlayerViewController];
        }
        else
        {
            [_playerViewController.view removeFromSuperview];
            _playerViewController = nil;
            [self usePlayerLayer];
        }
    }
}

- (void)setProgressUpdateInterval:(float)progressUpdateInterval
{
    _progressUpdateInterval = progressUpdateInterval;
    
    if (_timeObserver) {
        [self removePlayerTimeObserver];
        [self addPlayerTimeObserver];
    }
}

- (void)setLicenseUrl:(NSString*)licenseUrl
{
    _licenseUrl = licenseUrl;
}

- (void)setDeviceId:(NSString*)deviceId
{
    _deviceId = deviceId;
}

- (void)setCustomerId:(NSString*)customerId
{
    _customerId = customerId;
}

- (void)setDrmType:(NSString*)drmType
{
    _drmType = drmType;
}

- (void)setAuthToken:(NSString*)authToken
{
    _authToken = authToken;
}

- (void)setBase64CertificateString:(NSString*)base64CertificateString
{
    _base64CertificateString = base64CertificateString;
    if (_base64CertificateString != nil) {
        _licenseServerCertificateData = [[NSData alloc] initWithBase64EncodedString:_base64CertificateString options:0];
    } else {
        _licenseServerCertificateData = nil;
    }
}

- (void)removePlayerLayer
{
    [_playerLayer removeFromSuperlayer];
    if (_playerLayerObserverSet) {
        [_playerLayer removeObserver:self forKeyPath:readyForDisplayKeyPath];
        _playerLayerObserverSet = NO;
    }
    _playerLayer = nil;
}

#pragma mark - RCTVideoPlayerViewControllerDelegate

- (void)videoPlayerViewControllerWillDismiss:(AVPlayerViewController *)playerViewController
{
    if (_playerViewController == playerViewController && _fullscreenPlayerPresented && self.onVideoFullscreenPlayerWillDismiss)
    {
        self.onVideoFullscreenPlayerWillDismiss(@{@"target": self.reactTag});
    }
}

- (void)videoPlayerViewControllerDidDismiss:(AVPlayerViewController *)playerViewController
{
    if (_playerViewController == playerViewController && _fullscreenPlayerPresented)
    {
        _fullscreenPlayerPresented = false;
        _presentingViewController = nil;
        _playerViewController = nil;
        [self applyModifiers];
        if(self.onVideoFullscreenPlayerDidDismiss) {
            self.onVideoFullscreenPlayerDidDismiss(@{@"target": self.reactTag});
        }
    }
}

#pragma mark - React View Management

- (void)insertReactSubview:(UIView *)view atIndex:(NSInteger)atIndex
{
    // We are early in the game and somebody wants to set a subview.
    // That can only be in the context of playerViewController.
    if( !_controls && !_playerLayer && !_playerViewController )
    {
        [self setControls:true];
    }
    
    if( _controls )
    {
        view.frame = self.bounds;
        [_playerViewController.contentOverlayView insertSubview:view atIndex:atIndex];
    }
    else
    {
        RCTLogError(@"video cannot have any subviews");
    }
    return;
}

- (void)removeReactSubview:(UIView *)subview
{
    if( _controls )
    {
        [subview removeFromSuperview];
    }
    else
    {
        RCTLogError(@"video cannot have any subviews");
    }
    return;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    if( _controls )
    {
        _playerViewController.view.frame = self.bounds;
        
        // also adjust all subviews of contentOverlayView
        for (UIView* subview in _playerViewController.contentOverlayView.subviews) {
            subview.frame = self.bounds;
        }
    }
    else
    {
        [CATransaction begin];
        [CATransaction setAnimationDuration:0];
        _playerLayer.frame = self.bounds;
        [CATransaction commit];
    }
}

#pragma mark - Lifecycle

- (void)removeFromSuperview
{
    [_player pause];
    if (_playbackRateObserverRegistered) {
        [_player removeObserver:self forKeyPath:playbackRate context:nil];
        [_player removeObserver:self forKeyPath:statusKeyPath context:nil];
        _playbackRateObserverRegistered = NO;
    }
    _player = nil;
    
    [self removePlayerLayer];
    
    [_playerViewController.view removeFromSuperview];
    _playerViewController = nil;
    
    [self removePlayerTimeObserver];
    [self removePlayerItemObservers];
    
    _eventDispatcher = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [super removeFromSuperview];
}

#pragma mark - AVAssetResourceLoaderDelegate

-(BOOL) resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    // GET contentIdentifierData
    NSURLRequest* request = loadingRequest.request;
    NSURL* requestURL = request.URL;
    NSString* contentIdentifierString = requestURL.host;
    NSData* contentIdentifierData = [contentIdentifierString dataUsingEncoding:NSUTF8StringEncoding];
    
    // CALCULATE SPC DATA
    NSError *error = nil;
    NSData *spcData = [loadingRequest streamingContentKeyRequestDataForApp:_licenseServerCertificateData contentIdentifier:contentIdentifierData options:nil error:&error];
    UIDevice * currentDevice = [UIDevice currentDevice];
    
    // PRAPARE REQUEST PAYLOAD CONTAINING SPC DATA
    NSMutableDictionary *httpPayloadDict = [NSMutableDictionary dictionary];
    httpPayloadDict[@"Payload"] = [spcData base64EncodedStringWithOptions:0];
    if (_authToken) {
        httpPayloadDict[@"AuthToken"] = _authToken;
    } else {
        httpPayloadDict[@"LatensRegistration"] = [NSMutableDictionary dictionary];
        httpPayloadDict[@"LatensRegistration"][@"CustomerName"] = _customerId;
        httpPayloadDict[@"LatensRegistration"][@"AccountName"] = @"PlayReadyAccount";
        httpPayloadDict[@"LatensRegistration"][@"PortalId"] = _deviceId;
        httpPayloadDict[@"LatensRegistration"][@"FriendlyName"] = @"Swoop FairPlay Test";
        httpPayloadDict[@"LatensRegistration"][@"DeviceInfo"] = [NSMutableDictionary dictionary];
        httpPayloadDict[@"LatensRegistration"][@"DeviceInfo"][@"FormatVersion"] = @"1";
        httpPayloadDict[@"LatensRegistration"][@"DeviceInfo"][@"DeviceType"] = @"Device";
        httpPayloadDict[@"LatensRegistration"][@"DeviceInfo"][@"OSType"] = [currentDevice systemName];
        httpPayloadDict[@"LatensRegistration"][@"DeviceInfo"][@"OSVersion"] = [currentDevice systemVersion];
        httpPayloadDict[@"LatensRegistration"][@"DeviceInfo"][@"DRMProvider"] = @"Apple";
        httpPayloadDict[@"LatensRegistration"][@"DeviceInfo"][@"DRMVersion"] = @"1";
        httpPayloadDict[@"LatensRegistration"][@"DeviceInfo"][@"DRMType"] = _drmType;
        httpPayloadDict[@"LatensRegistration"][@"DeviceInfo"][@"DeviceVendor"] = @"Apple";
        httpPayloadDict[@"LatensRegistration"][@"DeviceInfo"][@"DeviceModel"] = [currentDevice model];        
    }
    
    NSData *httpPayloadJsonData = [NSJSONSerialization dataWithJSONObject:httpPayloadDict options:NSJSONWritingPrettyPrinted error:&error];
    NSData* httpPayloadData = [[httpPayloadJsonData base64EncodedStringWithOptions:0] dataUsingEncoding:NSUTF8StringEncoding];
    
    // PREPARE LICENSE CALL
    NSMutableURLRequest *key_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_licenseUrl]];
    [key_request setHTTPMethod:@"POST"];
    [key_request setHTTPBody:httpPayloadData];
    
    // GET LICENSE
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration delegate:nil delegateQueue:nil];
    NSURLSessionTask *task = [session dataTaskWithRequest:key_request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSDictionary *dataDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *base64licenseString = nil;
        base64licenseString = dataDict[@"license"];
        //NSLog(@"TADAAM - base64licenseString: %@", base64licenseString);
        NSData *encodedLicenseData = nil;
        if (base64licenseString) {
            encodedLicenseData = [[NSData alloc] initWithBase64EncodedString:base64licenseString options:0];
        }
        [loadingRequest.dataRequest respondWithData:encodedLicenseData];
        [loadingRequest finishLoading];
    }];
    [task resume];
    return true;
}

@end
