package com.brentvatne.exoplayer.bitrate;

public class LatensPerformanceBitrateAdaptionPreset implements BitrateAdaptionPreset {

    @Override
    public String name() {
        return "Latens performance";
    }

    @Override
    public float bandwidthFraction() {
        return 0.8F;
    }

    @Override
    public int bandwidthMeterMaxWeight() {
        return 3000;
    }

    @Override
    public int maxDurationForQualityDecreaseMs() {
        return 15000;
    }

    @Override
    public int minDurationToRetainAfterDiscardMs() {
        return 15000;
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