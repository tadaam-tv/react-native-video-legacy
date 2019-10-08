package com.brentvatne.exoplayer.bitrate;

public class LatensDefaultBitrateAdaptionPreset implements BitrateAdaptionPreset {

    @Override
    public String name() {
        return "Latens default";
    }

    @Override
    public float bandwidthFraction() {
        return 0.75f;
    }

    @Override
    public int bandwidthMeterMaxWeight() {
        return 1000;
    }

    @Override
    public int maxDurationForQualityDecreaseMs() {
        return 30000;
    }

    @Override
    public int minDurationToRetainAfterDiscardMs() {
        return 30000;
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