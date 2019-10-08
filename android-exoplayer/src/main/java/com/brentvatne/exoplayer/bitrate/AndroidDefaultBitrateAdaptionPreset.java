package com.brentvatne.exoplayer.bitrate;

import com.google.android.exoplayer2.DefaultLoadControl;
import com.google.android.exoplayer2.trackselection.AdaptiveTrackSelection;
import com.google.android.exoplayer2.upstream.DefaultBandwidthMeter;

public class AndroidDefaultBitrateAdaptionPreset implements BitrateAdaptionPreset {

    @Override
    public String name() {
        return "Android default";
    }

    @Override
    public float bandwidthFraction() {
        return AdaptiveTrackSelection.DEFAULT_BANDWIDTH_FRACTION;
    }

    @Override
    public int bandwidthMeterMaxWeight() {
        return DefaultBandwidthMeter.DEFAULT_MAX_WEIGHT; // 2000
    }

    @Override
    public int maxDurationForQualityDecreaseMs() {
        return AdaptiveTrackSelection.DEFAULT_MAX_DURATION_FOR_QUALITY_DECREASE_MS; // 25000
    }

    @Override
    public int minDurationToRetainAfterDiscardMs() {
        return AdaptiveTrackSelection.DEFAULT_MIN_DURATION_TO_RETAIN_AFTER_DISCARD_MS; // 25000
    }

    @Override
    public int minDurationForQualityIncreaseMs() {
        return AdaptiveTrackSelection.DEFAULT_MIN_DURATION_FOR_QUALITY_INCREASE_MS; // 10000
    }

    @Override
    public int maxInitialBitrate() {
        return AdaptiveTrackSelection.DEFAULT_MAX_INITIAL_BITRATE; // 800000
    }

    @Override
    public float bufferedFractionToLiveEdgeForQualityIncrease() {
        return AdaptiveTrackSelection.DEFAULT_BUFFERED_FRACTION_TO_LIVE_EDGE_FOR_QUALITY_INCREASE;
    }

    @Override
    public int bufferForPlaybackMs() {
        return DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS; // 2500
    }
}