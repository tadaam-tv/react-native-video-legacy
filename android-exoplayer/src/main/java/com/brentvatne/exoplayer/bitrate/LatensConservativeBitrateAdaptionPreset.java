package com.brentvatne.exoplayer.bitrate;

import com.google.android.exoplayer2.DefaultLoadControl;
import com.google.android.exoplayer2.trackselection.AdaptiveTrackSelection;
import com.google.android.exoplayer2.upstream.DefaultBandwidthMeter;

public class LatensConservativeBitrateAdaptionPreset implements BitrateAdaptionPreset {

    @Override
    public String name() {
        return "Latens conservative";
    }

    @Override
    public float bandwidthFraction() {
        return 0.6F;
    }

    @Override
    public int bandwidthMeterMaxWeight() {
        return 500;
    }

    @Override
    public int maxDurationForQualityDecreaseMs() {
        return 75000;
    }

    @Override
    public int minDurationToRetainAfterDiscardMs() {
        return 75000;
    }

    @Override
    public int minDurationForQualityIncreaseMs() {
        return 10000;
    }

    @Override
    public int maxInitialBitrate() {
        return 400000;
    }

    @Override
    public float bufferedFractionToLiveEdgeForQualityIncrease() {
        return 0.85f;
    }

    @Override
    public int bufferForPlaybackMs() {
        return 2000;
    }
}