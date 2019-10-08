package com.brentvatne.exoplayer.bitrate;

/*public enum BitrateAdaptionPreset {
    ANDROID_DEFAULT,
    LATENS_CONSERVATIVE,
    LATENS_PERFORMANCE,
    LATENS_DEFAULT,
    TADAAM_DEFAULT
}*/

public interface BitrateAdaptionPreset {

    String name();

    /* The fraction of the available bandwidth that the selection should
     *     consider available for use. Setting to a value less than 1 is recommended to account for
     *     inaccuracies in the bandwidth estimator. */
    float bandwidthFraction();


    /* The default maximum weight for the bandwidth meter's sliding window. */
    int bandwidthMeterMaxWeight();

    /* The maximum duration of buffered data required for the
     *     selected track to switch to one of lower quality. */
    int maxDurationForQualityDecreaseMs();

    /* When switching to a track of significantly higher
     *     quality, the selection may indicate that media already buffered at the lower quality can
     *     be discarded to speed up the switch. This is the minimum duration of media that must be
     *     retained at the lower quality. */
    int minDurationToRetainAfterDiscardMs();

    /* The minimum duration of buffered data required for the
     *     selected track to switch to one of higher quality. */
    int minDurationForQualityIncreaseMs();

    /* The maximum bitrate in bits per second that should be assumed when a
     *     bandwidth estimate is unavailable. */
    int maxInitialBitrate();

    /* For live streaming, the fraction of the
     *     duration from current playback position to the live edge that has to be buffered before
     *     the selected track can be switched to one of higher quality. This parameter is only
     *     applied when the playback position is closer to the live edge than {@code
     *     minDurationForQualityIncreaseMs}, which would otherwise prevent switching to a higher
     *     quality from happening. */
    float bufferedFractionToLiveEdgeForQualityIncrease();

    /* The duration of media that must be buffered for playback to start or
     *     resume following a user action such as a seek, in milliseconds. */
    int bufferForPlaybackMs();
}