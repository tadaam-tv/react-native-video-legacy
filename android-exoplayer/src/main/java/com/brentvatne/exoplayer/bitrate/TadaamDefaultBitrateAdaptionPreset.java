package com.brentvatne.exoplayer.bitrate;

import com.google.android.exoplayer2.trackselection.AdaptiveTrackSelection;
import com.google.android.exoplayer2.upstream.DefaultBandwidthMeter;

public class TadaamDefaultBitrateAdaptionPreset implements BitrateAdaptionPreset {

    @Override
    public String name() {
        return "Tadaam default";
    }

    @Override
    public float bandwidthFraction() {
        return 0.8f;
    }

    @Override
    public int bandwidthMeterMaxWeight() {
        return 3000;
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
        return 10000;
    }

    @Override
    public int maxInitialBitrate() {
        return 1600000;
    }

    @Override
    public float bufferedFractionToLiveEdgeForQualityIncrease() {
        return 0.85f;
    }

    @Override
    public int bufferForPlaybackMs() {
        return 4000;
    }
}