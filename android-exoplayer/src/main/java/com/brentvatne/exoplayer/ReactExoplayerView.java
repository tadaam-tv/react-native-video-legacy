package com.brentvatne.exoplayer;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Handler;
import android.os.Message;
import androidx.annotation.Nullable;
import android.text.TextUtils;
import android.util.Log;
import android.view.View;
import android.view.Window;
import android.view.accessibility.CaptioningManager;
import android.widget.FrameLayout;

import com.brentvatne.exoplayer.bitrate.BitrateAdaptionPreset;
import com.brentvatne.exoplayer.bitrate.TadaamDefaultBitrateAdaptionPreset;
import com.brentvatne.exoplayer.latens.LatensMediaDrmCallback;
import com.brentvatne.react.R;
import com.brentvatne.receiver.AudioBecomingNoisyReceiver;
import com.brentvatne.receiver.BecomingNoisyListener;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Dynamic;
import com.facebook.react.bridge.LifecycleEventListener;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.uimanager.ThemedReactContext;
import com.google.android.exoplayer2.C;
import com.google.android.exoplayer2.DefaultLoadControl;
import com.google.android.exoplayer2.DefaultRenderersFactory;
import com.google.android.exoplayer2.ExoPlaybackException;
import com.google.android.exoplayer2.ExoPlayer;
import com.google.android.exoplayer2.ExoPlayerFactory;
import com.google.android.exoplayer2.Format;
import com.google.android.exoplayer2.ParserException;
import com.google.android.exoplayer2.PlaybackParameters;
import com.google.android.exoplayer2.Player;
import com.google.android.exoplayer2.SimpleExoPlayer;
import com.google.android.exoplayer2.Timeline;
import com.google.android.exoplayer2.drm.DefaultDrmSessionManager;
import com.google.android.exoplayer2.drm.DrmSessionManager;
import com.google.android.exoplayer2.drm.FrameworkMediaCrypto;
import com.google.android.exoplayer2.drm.FrameworkMediaDrm;
import com.google.android.exoplayer2.drm.UnsupportedDrmException;
import com.google.android.exoplayer2.mediacodec.MediaCodecRenderer;
import com.google.android.exoplayer2.mediacodec.MediaCodecUtil;
import com.google.android.exoplayer2.metadata.Metadata;
import com.google.android.exoplayer2.metadata.MetadataRenderer;
import com.google.android.exoplayer2.source.BehindLiveWindowException;
import com.google.android.exoplayer2.source.ExtractorMediaSource;
import com.google.android.exoplayer2.source.MediaSource;
import com.google.android.exoplayer2.source.TrackGroupArray;
import com.google.android.exoplayer2.source.dash.DashMediaSource;
import com.google.android.exoplayer2.source.dash.DefaultDashChunkSource;
import com.google.android.exoplayer2.trackselection.AdaptiveTrackSelection;
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector;
import com.google.android.exoplayer2.trackselection.FixedTrackSelection;
import com.google.android.exoplayer2.trackselection.MappingTrackSelector;
import com.google.android.exoplayer2.trackselection.TrackSelectionArray;
import com.google.android.exoplayer2.upstream.BandwidthMeter;
import com.google.android.exoplayer2.upstream.DataSource;
import com.google.android.exoplayer2.upstream.DefaultAllocator;
import com.google.android.exoplayer2.upstream.DefaultBandwidthMeter;
import com.google.android.exoplayer2.upstream.DefaultDataSourceFactory;
import com.google.android.exoplayer2.upstream.DefaultHttpDataSourceFactory;
import com.google.android.exoplayer2.upstream.HttpDataSource;
import com.google.android.exoplayer2.util.Clock;
import com.google.android.exoplayer2.util.Util;

import java.net.CookieHandler;
import java.net.CookieManager;
import java.net.CookiePolicy;
import java.lang.Math;
import java.util.Map;
import java.lang.Object;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import android.view.WindowManager;

@SuppressLint("ViewConstructor")
class ReactExoplayerView extends FrameLayout implements
        LifecycleEventListener,
        ExoPlayer.EventListener,
        BecomingNoisyListener,
        AudioManager.OnAudioFocusChangeListener,
        MetadataRenderer.Output,
        DefaultDrmSessionManager.EventListener {

    private static final String TAG = "ReactExoplayerView";

    private static final String ERROR_CODE_DRM = "TDM_PLAYER_DRM011";

    private static final DefaultBandwidthMeter BANDWIDTH_METER = new DefaultBandwidthMeter();
    private static final CookieManager DEFAULT_COOKIE_MANAGER;
    private static final int SHOW_PROGRESS = 1;

    static {
        DEFAULT_COOKIE_MANAGER = new CookieManager();
        DEFAULT_COOKIE_MANAGER.setCookiePolicy(CookiePolicy.ACCEPT_ORIGINAL_SERVER);
    }

    private final VideoEventEmitter eventEmitter;

    private Handler mainHandler;
    private ExoPlayerView exoPlayerView;

    private DefaultDataSourceFactory mChunkSourceFactory, mMediaDataSourceFactory;

    private SimpleExoPlayer player;
    private DefaultTrackSelector trackSelector;
    private boolean playerNeedsSource;

    private int resumeWindow;
    private long resumePosition;
    private boolean loadVideoStarted;
    private boolean isFullscreen;
    private boolean isInBackground;
    private boolean isPaused;
    private boolean isBuffering;
    private float rate = 1f;

    private DefaultBandwidthMeter mBandwidthMeter;

    private int minBufferMs = DefaultLoadControl.DEFAULT_MIN_BUFFER_MS;
    private int maxBufferMs = DefaultLoadControl.DEFAULT_MAX_BUFFER_MS;
    private int bufferForPlaybackAfterRebufferMs = DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS;
    private int mBufferForPlaybackMs = DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS;

    private int mMinDurationForQualityIncreaseMs;
    private int mMaxDurationForQualityDecreaseMs;
    private int mMinDurationToRetainAfterDiscardMs;
    private float mBandwidthFraction;
    private int mBandwidthMeterMaxWeight;
    private int mMaxInitialBitrate;
    private float mBufferedFractionToLiveEdgeForQualityIncrease;

    private AtomicInteger mMaxBitrate = new AtomicInteger(0);

    private static String userAgent = "tadaam";

    // Props from React
    private Uri srcUri;
    private String extension;
    private boolean repeat;
    private String audioTrackType;
    private Dynamic audioTrackValue;
    private ReadableArray audioTracks;
    private String textTrackType;
    private Dynamic textTrackValue;
    private ReadableArray textTracks;
    private boolean disableFocus;
    private float mProgressUpdateInterval = 250.0f;
    private boolean playInBackground = false;
    private UUID drmUUID = null;
    private String drmLicenseUrl = null;
    private String customerId = null;
    private String deviceId = null;
    private String[] drmLicenseHeader = null;
    private boolean useTextureView = false;
    private Map<String, String> requestHeaders;
    // \ End props

    // React
    private final ThemedReactContext themedReactContext;
    private final AudioManager audioManager;
    private final AudioBecomingNoisyReceiver audioBecomingNoisyReceiver;

    @SuppressLint("HandlerLeak")
    private final Handler progressHandler = new Handler() {
        @Override
        public void handleMessage(Message msg) {
            switch (msg.what) {
                case SHOW_PROGRESS:
                    if (player != null
                            && player.getPlaybackState() == ExoPlayer.STATE_READY
                            && player.getPlayWhenReady()
                    ) {
                        long pos = player.getCurrentPosition();
                        long bufferedDuration = player.getBufferedPercentage() * player.getDuration() / 100;
                        long currentBitrate = player.getVideoFormat() != null? player.getVideoFormat().bitrate : 0;
                        eventEmitter.progressChanged(pos, bufferedDuration, player.getDuration(), currentBitrate);
                        msg = obtainMessage(SHOW_PROGRESS);
                        sendMessageDelayed(msg, Math.round(mProgressUpdateInterval));
                    }
                    break;
            }
        }
    };

    public ReactExoplayerView(ThemedReactContext context) {
        super(context);
        this.themedReactContext = context;
        createViews();
        this.eventEmitter = new VideoEventEmitter(context);
        audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        themedReactContext.addLifecycleEventListener(this);
        audioBecomingNoisyReceiver = new AudioBecomingNoisyReceiver(themedReactContext);
        initAdaptionPreset(new TadaamDefaultBitrateAdaptionPreset());
    }

    @Override
    public void setId(int id) {
        super.setId(id);
        eventEmitter.setViewId(id);
    }

    public void setCustomerId(String customerId) {
        this.customerId = customerId;
    }

    public void setDeviceId(String deviceId) {
        this.deviceId = deviceId;
    }

    private void createViews() {
        clearResumePosition();

        mainHandler = new Handler();
        if (CookieHandler.getDefault() != DEFAULT_COOKIE_MANAGER) {
            CookieHandler.setDefault(DEFAULT_COOKIE_MANAGER);
        }

        LayoutParams layoutParams = new LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT);
        exoPlayerView = new ExoPlayerView(getContext());
        exoPlayerView.setLayoutParams(layoutParams);

        addView(exoPlayerView, 0, layoutParams);
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        Log.d("onAttachedToWindow", "drm url");
        initializePlayer();

        // Start KeepAwake
        activateKeepAwake();
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        stopPlayback();

        // Stop KeepAwake
        deactivateKeepAwake();
    }

    // KeepAwake
    public void activateKeepAwake() {
        final Activity activity = this.themedReactContext.getCurrentActivity();

        if (activity != null) {
            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                }
            });
        }
    }

    public void deactivateKeepAwake() {
        final Activity activity = this.themedReactContext.getCurrentActivity();

        if (activity != null) {
            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    activity.getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                }
            });
        }
    }

    // LifecycleEventListener implementation

    @Override
    public void onHostResume() {
        if (!playInBackground || !isInBackground) {
            setPlayWhenReady(!isPaused);
        }
        isInBackground = false;
    }

    @Override
    public void onHostPause() {
        isInBackground = true;
        if (playInBackground) {
            return;
        }
        setPlayWhenReady(false);
    }

    @Override
    public void onHostDestroy() {
        stopPlayback();
    }

    public void cleanUpResources() {
        stopPlayback();
    }


    // Internal methods

    /**
     * BitrateAdaptionPreset from TiMP_02_06_28092018
     * @param preset
     */
    private void initAdaptionPreset(BitrateAdaptionPreset preset) {
        Log.d("initAdaptionPreset", preset.name());
        mBandwidthFraction = preset.bandwidthFraction();
        mBandwidthMeterMaxWeight = preset.bandwidthMeterMaxWeight();
        mMaxDurationForQualityDecreaseMs = preset.maxDurationForQualityDecreaseMs();
        mMinDurationToRetainAfterDiscardMs = preset.minDurationToRetainAfterDiscardMs();
        mMinDurationForQualityIncreaseMs = preset.minDurationForQualityIncreaseMs();
        mMaxInitialBitrate = preset.maxInitialBitrate();
        mBufferedFractionToLiveEdgeForQualityIncrease = preset.bufferedFractionToLiveEdgeForQualityIncrease();
        mBufferForPlaybackMs = preset.bufferForPlaybackMs();
        mBandwidthMeter = new DefaultBandwidthMeter(mainHandler, null, mBandwidthMeterMaxWeight);
        mMediaDataSourceFactory = new DefaultDataSourceFactory(themedReactContext, null,
                new DefaultHttpDataSourceFactory(userAgent, null, 6000, 4000, false));
        mChunkSourceFactory = new DefaultDataSourceFactory(themedReactContext, mBandwidthMeter,
                new DefaultHttpDataSourceFactory(userAgent, mBandwidthMeter, 8000, 8000, false));
    }

    private void initializePlayer() {
        Log.d("initializePlayer", "drm url");
        if (player == null) {
            AdaptiveTrackSelection.Factory localFactory = new AdaptiveTrackSelection.Factory(
                    mBandwidthMeter,
                    mMaxInitialBitrate,
                    mMinDurationForQualityIncreaseMs,
                    mMaxDurationForQualityDecreaseMs,
                    mMinDurationToRetainAfterDiscardMs,
                    mBandwidthFraction,
                    mBufferedFractionToLiveEdgeForQualityIncrease,
                    AdaptiveTrackSelection.DEFAULT_MIN_TIME_BETWEEN_BUFFER_REEVALUTATION_MS,
                    Clock.DEFAULT);
            trackSelector = new DefaultTrackSelector(localFactory);
            DefaultAllocator allocator = new DefaultAllocator(true, C.DEFAULT_BUFFER_SEGMENT_SIZE);
            DefaultLoadControl defaultLoadControl = new DefaultLoadControl(allocator,
                    minBufferMs,
                    maxBufferMs,
                    mBufferForPlaybackMs,
                    bufferForPlaybackAfterRebufferMs,
                    26214400,
                    true);

            DrmSessionManager<FrameworkMediaCrypto> drmSessionManager = null;
            if (this.drmUUID != null) {
                try {
                    drmSessionManager = buildDrmSessionManager();
                } catch (UnsupportedDrmException e) {
                    int errorStringId = (e.reason == UnsupportedDrmException.REASON_UNSUPPORTED_SCHEME
                            ? R.string.error_drm_unsupported_scheme : R.string.error_drm_unknown);
                    String errorMsg = getResources().getString(errorStringId);
                    Log.d("Drm Info", getResources().getString(errorStringId));
                    eventEmitter.error(errorMsg, e);
                    return;
                }
            }
            DefaultRenderersFactory renderersFactory = new DefaultRenderersFactory(getContext(),
                    drmSessionManager, DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF);

            player = ExoPlayerFactory.newSimpleInstance(renderersFactory, trackSelector, defaultLoadControl);
            player.addListener(this);
            player.addMetadataOutput(this);
            exoPlayerView.setPlayer(player);
            audioBecomingNoisyReceiver.setListener(this);
            setPlayWhenReady(!isPaused);
            playerNeedsSource = true;

            PlaybackParameters params = new PlaybackParameters(rate, 1f);
            player.setPlaybackParameters(params);
            player.setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING);
            player.setRepeatMode(repeat? Player.REPEAT_MODE_ONE: Player.REPEAT_MODE_OFF);

        }
        if (playerNeedsSource && srcUri != null) {
            MediaSource mediaSource = buildMediaSource(srcUri, extension);
            boolean haveResumePosition = resumeWindow != C.INDEX_UNSET;
            if (haveResumePosition) {
                player.seekTo(resumeWindow, resumePosition);
            }
            player.prepare(mediaSource, !haveResumePosition, false);

            setMaxBitrate(mMaxBitrate.intValue());

            playerNeedsSource = false;

            eventEmitter.loadStart();
            loadVideoStarted = true;
        }
    }

    public void setMaxBitrate(int bitrate) {
        if (bitrate == 0) {
            mMaxBitrate.set(Integer.MAX_VALUE);
        } else {
            mMaxBitrate.set(bitrate);
        }
        DefaultTrackSelector.Parameters localParameters = trackSelector.getParameters().buildUpon().setMaxVideoBitrate(mMaxBitrate.intValue()).build();
        trackSelector.setParameters(localParameters);
    }

    private DrmSessionManager<FrameworkMediaCrypto> buildDrmSessionManager() throws UnsupportedDrmException {
        DrmHttpDataSourceFactory httpDataSourceFactory = new DrmHttpDataSourceFactory("sctv", null);
        LatensMediaDrmCallback drmCallback = new LatensMediaDrmCallback(this.drmLicenseUrl, deviceId, customerId, httpDataSourceFactory);
        FrameworkMediaDrm mediaDrm = FrameworkMediaDrm.newInstance(this.drmUUID);
        return new DefaultDrmSessionManager<>(this.drmUUID, mediaDrm, drmCallback, null, mainHandler, this);
    }

    public int inferContentType(Uri uri) {
        String path = uri.getPath();
        if (path == null) {
            return C.TYPE_OTHER;
        }
        String fileName = Util.toLowerInvariant(path);
        if (fileName.contains(".mpd")) {
            return C.TYPE_DASH;
        } else if (fileName.endsWith(".m3u8")) {
            return C.TYPE_HLS;
        } else if (fileName.matches(".*\\.ism(l)?(/manifest(\\(.+\\))?)?")) {
            return C.TYPE_SS;
        } else {
            return C.TYPE_OTHER;
        }
    }

    private MediaSource buildMediaSource(Uri uri, @Nullable String overrideExtension) {
        @C.ContentType int type = inferContentType(uri);
        switch (type) {
            case C.TYPE_DASH:
                DashMediaSource.Factory localFactory =
                        new DashMediaSource.Factory(new DefaultDashChunkSource.Factory(mChunkSourceFactory), mMediaDataSourceFactory);
                localFactory.setLivePresentationDelayMs(10000L);
                return localFactory.createMediaSource(uri, mainHandler, null);
            case C.TYPE_OTHER:
                return new ExtractorMediaSource.Factory(mMediaDataSourceFactory).createMediaSource(uri);
            case C.TYPE_SS: /*unsupported for now*/
            case C.TYPE_HLS: /*unsupported for now*/
            default: {
                throw new IllegalStateException("Unsupported type: " + type);
            }
        }
    }

    private void releasePlayer() {
        if (player != null) {
            updateResumePosition();
            player.release();
            player.setMetadataOutput(null);
            player = null;
            trackSelector = null;
        }
        progressHandler.removeMessages(SHOW_PROGRESS);
        themedReactContext.removeLifecycleEventListener(this);
        audioBecomingNoisyReceiver.removeListener();
    }

    private boolean requestAudioFocus() {
        if (disableFocus) {
            return true;
        }
        int result = audioManager.requestAudioFocus(this,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN);
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
    }

    private void setPlayWhenReady(boolean playWhenReady) {
        if (player == null) {
            return;
        }

        if (playWhenReady) {
            boolean hasAudioFocus = requestAudioFocus();
            if (hasAudioFocus) {
                player.setPlayWhenReady(true);
            }
        } else {
            player.setPlayWhenReady(false);
        }
    }

    private void startPlayback() {
        if (player != null) {
            switch (player.getPlaybackState()) {
                case ExoPlayer.STATE_IDLE:
                case ExoPlayer.STATE_ENDED:
                    initializePlayer();
                    break;
                case ExoPlayer.STATE_BUFFERING:
                case ExoPlayer.STATE_READY:
                    if (!player.getPlayWhenReady()) {
                        setPlayWhenReady(true);
                    }
                    break;
                default:
                    break;
            }

        } else {
            initializePlayer();
        }
        if (!disableFocus) {
            setKeepScreenOn(true);
        }
    }

    private void pausePlayback() {
        if (player != null) {
            if (player.getPlayWhenReady()) {
                setPlayWhenReady(false);
            }
        }
        setKeepScreenOn(false);
    }

    private void stopPlayback() {
        onStopPlayback();
        releasePlayer();
    }

    private void onStopPlayback() {
        if (isFullscreen) {
            setFullscreen(false);
        }
        setKeepScreenOn(false);
        audioManager.abandonAudioFocus(this);
    }

    private void updateResumePosition() {
        resumeWindow = player.getCurrentWindowIndex();
        resumePosition = player.isCurrentWindowSeekable() ? Math.max(0, player.getCurrentPosition())
                : C.TIME_UNSET;
    }

    private void clearResumePosition() {
        resumeWindow = C.INDEX_UNSET;
        resumePosition = C.TIME_UNSET;
    }

    @Override
    public void onAudioFocusChange(int focusChange) {
        switch (focusChange) {
            case AudioManager.AUDIOFOCUS_LOSS:
                eventEmitter.audioFocusChanged(false);
                break;
            case AudioManager.AUDIOFOCUS_GAIN:
                eventEmitter.audioFocusChanged(true);
                break;
            default:
                break;
        }

        if (player != null) {
            if (focusChange == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK) {
                // Lower the volume
                player.setVolume(0.8f);
            } else if (focusChange == AudioManager.AUDIOFOCUS_GAIN) {
                // Raise it back to normal
                player.setVolume(1);
            }
        }
    }

    // AudioBecomingNoisyListener implementation

    @Override
    public void onAudioBecomingNoisy() {
        eventEmitter.audioBecomingNoisy();
    }

    // ExoPlayer.EventListener implementation

    @Override
    public void onLoadingChanged(boolean isLoading) {
        // Do nothing.
    }

    @Override
    public void onPlayerStateChanged(boolean playWhenReady, int playbackState) {
        String text = "onStateChanged: playWhenReady=" + playWhenReady + ", playbackState=";
        switch (playbackState) {
            case ExoPlayer.STATE_IDLE:
                text += "idle";
                eventEmitter.idle();
                break;
            case ExoPlayer.STATE_BUFFERING:
                text += "buffering";
                onBuffering(true);
                break;
            case ExoPlayer.STATE_READY:
                text += "ready";
                eventEmitter.ready();
                onBuffering(false);
                startProgressHandler();
                videoLoaded();
                break;
            case ExoPlayer.STATE_ENDED:
                text += "ended";
                eventEmitter.end();
                onStopPlayback();
                break;
            default:
                text += "unknown";
                break;
        }
        Log.d(TAG, text);
    }

    private void startProgressHandler() {
        progressHandler.sendEmptyMessage(SHOW_PROGRESS);
    }

    private void videoLoaded() {
        if (loadVideoStarted) {
            loadVideoStarted = false;
            setSelectedAudioTrack(audioTrackType, audioTrackValue);
            setSelectedTextTrack(textTrackType, textTrackValue);
            Format videoFormat = player.getVideoFormat();
            int width = videoFormat != null ? videoFormat.width : 0;
            int height = videoFormat != null ? videoFormat.height : 0;
            eventEmitter.load(player.getDuration(), player.getCurrentPosition(), width, height,
                    getAudioTrackInfo(), getTextTrackInfo());
        }
    }

    private WritableArray getAudioTrackInfo() {
        WritableArray audioTracks = Arguments.createArray();

        MappingTrackSelector.MappedTrackInfo info = trackSelector.getCurrentMappedTrackInfo();
        int index = getTrackRendererIndex(C.TRACK_TYPE_AUDIO);
        if (info == null || index == C.INDEX_UNSET) {
            return audioTracks;
        }

        TrackGroupArray groups = info.getTrackGroups(index);
        for (int i = 0; i < groups.length; ++i) {
            Format format = groups.get(i).getFormat(0);
            WritableMap textTrack = Arguments.createMap();
            textTrack.putInt("index", i);
            textTrack.putString("title", format.id != null ? format.id : "");
            textTrack.putString("type", format.sampleMimeType);
            textTrack.putString("language", format.language != null ? format.language : "");
            audioTracks.pushMap(textTrack);
        }
        return audioTracks;
    }

    private WritableArray getTextTrackInfo() {
        WritableArray textTracks = Arguments.createArray();

        MappingTrackSelector.MappedTrackInfo info = trackSelector.getCurrentMappedTrackInfo();
        int index = getTrackRendererIndex(C.TRACK_TYPE_TEXT);
        if (info == null || index == C.INDEX_UNSET) {
            return textTracks;
        }

        TrackGroupArray groups = info.getTrackGroups(index);
        for (int i = 0; i < groups.length; ++i) {
            Format format = groups.get(i).getFormat(0);
            WritableMap textTrack = Arguments.createMap();
            textTrack.putInt("index", i);
            textTrack.putString("title", format.id != null ? format.id : "");
            textTrack.putString("type", format.sampleMimeType);
            textTrack.putString("language", format.language != null ? format.language : "");
            textTracks.pushMap(textTrack);
        }
        return textTracks;
    }

    private void onBuffering(boolean buffering) {
        if (isBuffering == buffering) {
            return;
        }

        isBuffering = buffering;
        if (buffering) {
            eventEmitter.buffering(true);
        } else {
            eventEmitter.buffering(false);
        }
    }

    @Override
    public void onPositionDiscontinuity(int reason) {
        if (playerNeedsSource) {
            // This will only occur if the user has performed a seek whilst in the error state. Update the
            // resume position so that if the user then retries, playback will resume from the position to
            // which they seeked.
            updateResumePosition();
        }
        // When repeat is turned on, reaching the end of the video will not cause a state change
        // so we need to explicitly detect it.
        if (reason == ExoPlayer.DISCONTINUITY_REASON_PERIOD_TRANSITION
                && player.getRepeatMode() == Player.REPEAT_MODE_ONE) {
            eventEmitter.end();
        }
    }

    @Override
    public void onTimelineChanged(Timeline timeline, Object manifest, int reason) {
        // Do nothing.
    }

    @Override
    public void onSeekProcessed() {
        // Do nothing.
    }

    @Override
    public void onShuffleModeEnabledChanged(boolean shuffleModeEnabled) {
        // Do nothing.
    }

    @Override
    public void onRepeatModeChanged(int repeatMode) {
        // Do nothing.
    }

    @Override
    public void onTracksChanged(TrackGroupArray trackGroups, TrackSelectionArray trackSelections) {
        // Do Nothing.
    }

    @Override
    public void onPlaybackParametersChanged(PlaybackParameters params) {
        eventEmitter.playbackRateChange(params.speed);
    }

    @Override
    public void onPlayerError(ExoPlaybackException e) {
        String errorString = null;
        Exception ex = e;
        if (e.type == ExoPlaybackException.TYPE_RENDERER) {
            Exception cause = e.getRendererException();
            if (cause instanceof MediaCodecRenderer.DecoderInitializationException) {
                // Special case for decoder initialization failures.
                MediaCodecRenderer.DecoderInitializationException decoderInitializationException =
                        (MediaCodecRenderer.DecoderInitializationException) cause;
                if (decoderInitializationException.decoderName == null) {
                    if (decoderInitializationException.getCause() instanceof MediaCodecUtil.DecoderQueryException) {
                        errorString = getResources().getString(R.string.error_querying_decoders);
                    } else if (decoderInitializationException.secureDecoderRequired) {
                        errorString = getResources().getString(R.string.error_no_secure_decoder,
                                decoderInitializationException.mimeType);
                    } else {
                        errorString = getResources().getString(R.string.error_no_decoder,
                                decoderInitializationException.mimeType);
                    }
                } else {
                    errorString = getResources().getString(R.string.error_instantiating_decoder,
                            decoderInitializationException.decoderName);
                }
            }
        } else if (e.type == ExoPlaybackException.TYPE_SOURCE) {
            ex = e.getSourceException();
            errorString = getResources().getString(R.string.unrecognized_media_format);
        }
        playerNeedsSource = true;
        if (isBehindLiveWindow(e) || isInvalidResponseCode(e)) {
            // restart player, don't surface error
            clearResumePosition();
            initializePlayer();
        } else {
            Log.d(TAG, "Catched unrecoverable error");
            updateResumePosition();

            // let error surface
            if (errorString != null) {
                eventEmitter.error(errorString, ex);
            }
        }
    }

    /**
     * Check for EDP's InvalidResponseCodeException
     */
    private static boolean isInvalidResponseCode(ExoPlaybackException e) {
        if (e.type != ExoPlaybackException.TYPE_SOURCE) {
            return false;
        }
        Throwable cause = e.getSourceException();
        while (cause != null) {
            if (cause instanceof HttpDataSource.InvalidResponseCodeException) {
                Log.d(TAG, "Catched InvalidResponseCodeException");
                return true;
            }
            cause = cause.getCause();
        }
        return false;
    }

    private static boolean isBehindLiveWindow(ExoPlaybackException e) {
        if (e.type != ExoPlaybackException.TYPE_SOURCE) {
            return false;
        }
        Throwable cause = e.getSourceException();
        while (cause != null) {
            if (cause instanceof BehindLiveWindowException) {
                return true;
            }
            cause = cause.getCause();
        }
        return false;
    }

    public int getTrackRendererIndex(int trackType) {
        int rendererCount = player.getRendererCount();
        for (int rendererIndex = 0; rendererIndex < rendererCount; rendererIndex++) {
            if (player.getRendererType(rendererIndex) == trackType) {
                return rendererIndex;
            }
        }
        return C.INDEX_UNSET;
    }

    @Override
    public void onMetadata(Metadata metadata) {
        eventEmitter.timedMetadata(metadata);
    }

    // ReactExoplayerViewManager public api

    public void setSrc(final Uri uri, final String extension, Map<String, String> headers) {
        if (uri != null) {
            boolean isOriginalSourceNull = srcUri == null;
            boolean isSourceEqual = uri.equals(srcUri);

            this.srcUri = uri;
            this.extension = extension;
            this.requestHeaders = headers;

            if (!isOriginalSourceNull && !isSourceEqual) {
                reloadSource();
            }
        }
    }

    public void setProgressUpdateInterval(final float progressUpdateInterval) {
        mProgressUpdateInterval = progressUpdateInterval;
    }

    public void setRawSrc(final Uri uri, final String extension) {
        if (uri != null) {
            boolean isOriginalSourceNull = srcUri == null;
            boolean isSourceEqual = uri.equals(srcUri);

            this.srcUri = uri;
            this.extension = extension;

            if (!isOriginalSourceNull && !isSourceEqual) {
                reloadSource();
            }
        }
    }

    public void setTextTracks(ReadableArray textTracks) {
        this.textTracks = textTracks;
        reloadSource();
    }

    private void reloadSource() {
        playerNeedsSource = true;
        initializePlayer();
    }

    public void setResizeModeModifier(@ResizeMode.Mode int resizeMode) {
        exoPlayerView.setResizeMode(resizeMode);
    }

    public void setRepeatModifier(boolean repeat) {
        if (player != null) {
            if (repeat) {
                player.setRepeatMode(Player.REPEAT_MODE_ONE);
            } else {
                player.setRepeatMode(Player.REPEAT_MODE_OFF);
            }
        }
        this.repeat = repeat;
    }

    public void setSelectedTrack(int trackType, String type, Dynamic value) {
        int rendererIndex = getTrackRendererIndex(trackType);
        if (rendererIndex == C.INDEX_UNSET) {
            return;
        }
        MappingTrackSelector.MappedTrackInfo info = trackSelector.getCurrentMappedTrackInfo();
        if (info == null) {
            return;
        }

        TrackGroupArray groups = info.getTrackGroups(rendererIndex);
        int trackIndex = C.INDEX_UNSET;

        if (TextUtils.isEmpty(type)) {
            type = "default";
        }

        if (type.equals("disabled")) {
            trackSelector.setSelectionOverride(rendererIndex, groups, null);
            return;
        } else if (type.equals("language")) {
            for (int i = 0; i < groups.length; ++i) {
                Format format = groups.get(i).getFormat(0);
                if (format.language != null && format.language.equals(value.asString())) {
                    trackIndex = i;
                    break;
                }
            }
        } else if (type.equals("title")) {
            for (int i = 0; i < groups.length; ++i) {
                Format format = groups.get(i).getFormat(0);
                if (format.id != null && format.id.equals(value.asString())) {
                    trackIndex = i;
                    break;
                }
            }
        } else if (type.equals("index")) {
            if (value.asInt() < groups.length) {
                trackIndex = value.asInt();
            }
        } else { // default
            if (rendererIndex == C.TRACK_TYPE_TEXT) { // Use system settings if possible
                int sdk = android.os.Build.VERSION.SDK_INT;
                if (sdk > 18 && groups.length > 0) {
                    CaptioningManager captioningManager
                            = (CaptioningManager) themedReactContext.getSystemService(Context.CAPTIONING_SERVICE);
                    if (captioningManager != null && captioningManager.isEnabled()) {
                        trackIndex = getTrackIndexForDefaultLocale(groups);
                    }
                } else {
                    trackSelector.setSelectionOverride(rendererIndex, groups, null);
                    return;
                }
            } else if (rendererIndex == C.TRACK_TYPE_AUDIO) {
                trackIndex = getTrackIndexForDefaultLocale(groups);
            }
        }

        if (trackIndex == C.INDEX_UNSET) {
            trackSelector.clearSelectionOverrides(rendererIndex);
            return;
        }

        MappingTrackSelector.SelectionOverride override
                = new MappingTrackSelector.SelectionOverride(
                new FixedTrackSelection.Factory(), trackIndex, 0);
        trackSelector.setSelectionOverride(rendererIndex, groups, override);
    }

    private int getTrackIndexForDefaultLocale(TrackGroupArray groups) {
        if (groups.length == 0) { // Avoid a crash if we try to select a non-existant group
            return C.INDEX_UNSET;
        }

        int trackIndex = 0; // default if no match
        String locale2 = Locale.getDefault().getLanguage(); // 2 letter code
        String locale3 = Locale.getDefault().getISO3Language(); // 3 letter code
        for (int i = 0; i < groups.length; ++i) {
            Format format = groups.get(i).getFormat(0);
            String language = format.language;
            if (language != null && (language.equals(locale2) || language.equals(locale3))) {
                trackIndex = i;
                break;
            }
        }
        return trackIndex;
    }

    public void setSelectedAudioTrack(String type, Dynamic value) {
        audioTrackType = type;
        audioTrackValue = value;
        setSelectedTrack(C.TRACK_TYPE_AUDIO, audioTrackType, audioTrackValue);
    }

    public void setSelectedTextTrack(String type, Dynamic value) {
        textTrackType = type;
        textTrackValue = value;
        setSelectedTrack(C.TRACK_TYPE_TEXT, textTrackType, textTrackValue);
    }

    public void setPausedModifier(boolean paused) {
        isPaused = paused;
        if (player != null) {
            if (!paused) {
                startPlayback();
            } else {
                pausePlayback();
            }
        }
    }

    public void setMutedModifier(boolean muted) {
        if (player != null) {
            player.setVolume(muted ? 0 : 1);
        }
    }


    public void setVolumeModifier(float volume) {
        if (player != null) {
            player.setVolume(volume);
        }
    }

    public void seekTo(long positionMs) {
        if (player != null) {
            eventEmitter.seek(player.getCurrentPosition(), positionMs);
            player.seekTo(positionMs);
        }
    }

    public void setRateModifier(float newRate) {
        rate = newRate;

        if (player != null) {
            PlaybackParameters params = new PlaybackParameters(rate, 1f);
            player.setPlaybackParameters(params);
        }
    }


    public void setPlayInBackground(boolean playInBackground) {
        this.playInBackground = playInBackground;
    }

    public void setDisableFocus(boolean disableFocus) {
        this.disableFocus = disableFocus;
    }

    /**
     * @param drmName
     */
    public void setDrmName(String drmName) throws ParserException {
        switch (Util.toLowerInvariant(drmName)) {
            case "widevine":
                this.drmUUID = C.WIDEVINE_UUID;
                break;
            case "playready":
                this.drmUUID = C.PLAYREADY_UUID;
                break;
            case "cenc":
                this.drmUUID = C.CLEARKEY_UUID;
                break;
            default:
                try {
                    this.drmUUID = UUID.fromString(drmName);
                } catch (RuntimeException e) {
                    String errorString = "Unsupported drm type: " + drmName;
                    eventEmitter.error(errorString, e);
                    throw new ParserException(errorString);
                }
        }
        Log.d("setDrmLicenseUrl", drmName);
    }

    public void setDrmLicenseUrl(String licenseUrl) {
        Log.d("setDrmLicenseUrl", licenseUrl);
        this.drmLicenseUrl = licenseUrl;
    }

    public void setDrmLicenseHeader(String[] header) {
        Log.d("setDrmLicenseHeader", header.toString());
        this.drmLicenseHeader = header;
    }

    @Override
    public void onDrmKeysLoaded() {
        Log.d("DRM Info", "onDrmKeysLoaded");
    }

    @Override
    public void onDrmSessionManagerError(Exception e) {
        Log.d("DRM Info", "onDrmSessionManagerError");
        String errorString = String.format("Drm error, %s", e.getMessage());
        eventEmitter.error(errorString, e, ERROR_CODE_DRM);
    }

    @Override
    public void onDrmKeysRestored() {
        Log.d("DRM Info", "onDrmKeysRestored");
    }

    @Override
    public void onDrmKeysRemoved() {
        Log.d("DRM Info", "onDrmKeysRestored");
    }

    public void setFullscreen(boolean fullscreen) {
        if (fullscreen == isFullscreen) {
            return; // Avoid generating events when nothing is changing
        }
        isFullscreen = fullscreen;

        Activity activity = themedReactContext.getCurrentActivity();
        if (activity == null) {
            return;
        }
        Window window = activity.getWindow();
        View decorView = window.getDecorView();
        int uiOptions;
        if (isFullscreen) {
            if (Util.SDK_INT >= 19) { // 4.4+
                uiOptions = SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | SYSTEM_UI_FLAG_FULLSCREEN;
            } else {
                uiOptions = SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | SYSTEM_UI_FLAG_FULLSCREEN;
            }
            eventEmitter.fullscreenWillPresent();
            decorView.setSystemUiVisibility(uiOptions);
            eventEmitter.fullscreenDidPresent();
        } else {
            uiOptions = View.SYSTEM_UI_FLAG_VISIBLE;
            eventEmitter.fullscreenWillDismiss();
            decorView.setSystemUiVisibility(uiOptions);
            eventEmitter.fullscreenDidDismiss();
        }
    }

    public void setUseTextureView(boolean useTextureView) {
        exoPlayerView.setUseTextureView(useTextureView);
    }

    public void setBufferConfig(int newMinBufferMs, int newMaxBufferMs, int newBufferForPlaybackMs, int newBufferForPlaybackAfterRebufferMs) {
        minBufferMs = newMinBufferMs;
        maxBufferMs = newMaxBufferMs;
        mBufferForPlaybackMs = newBufferForPlaybackMs;
        bufferForPlaybackAfterRebufferMs = newBufferForPlaybackAfterRebufferMs;
        releasePlayer();
        initializePlayer();
    }
}
