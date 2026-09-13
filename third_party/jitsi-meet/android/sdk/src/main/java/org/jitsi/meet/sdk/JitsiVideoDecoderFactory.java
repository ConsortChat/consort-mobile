package org.jitsi.meet.sdk;

/*
 *  Copyright 2017 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

import android.media.MediaCodecInfo;
import androidx.annotation.Nullable;

import com.oney.WebRTCModule.webrtcutils.SoftwareVideoDecoderFactoryProxy;

import org.webrtc.EglBase;
import org.webrtc.HardwareVideoDecoderFactory;
import org.webrtc.JitsiPlatformVideoDecoderFactory;
import org.webrtc.Predicate;
import org.webrtc.VideoCodecInfo;
import org.webrtc.VideoDecoder;
import org.webrtc.VideoDecoderFactory;
import org.webrtc.VideoDecoderFallback;

import java.util.Arrays;
import java.util.LinkedHashSet;

/**
 * Custom decoder factory which uses HW decoders and falls back to SW.
 */
public class JitsiVideoDecoderFactory implements VideoDecoderFactory {
    private final VideoDecoderFactory hardwareVideoDecoderFactory;
    private final VideoDecoderFactory softwareVideoDecoderFactory = new SoftwareVideoDecoderFactoryProxy();
    private final VideoDecoderFactory platformSoftwareVideoDecoderFactory;

    /**
     * Predicate to filter out the AV1 hardware decoder, as we've seen decoding issues with it.
     */
    private static final String GOOGLE_AV1_DECODER = "c2.google.av1";

    /**
     * Consort: Samsung Exynos hardware decoders, as found on Pixel (Tensor) and Samsung Exynos phones. On a
     * Pixel 9 Pro XL, joining a call where a screen share was already running left the share black: the
     * c2.exynos.vp8 or c2.exynos.vp9 decoder produced output, was released and re-initialised around the
     * first frames, and the renderer never received a frame for the rest of the call. The same joins
     * rendered every time when the share was decoded in software (AV1, which this factory already keeps
     * off hardware).
     */
    private static final String[] EXYNOS_DECODER_PREFIXES = { "c2.exynos.", "OMX.Exynos." };

    private static final Predicate<MediaCodecInfo> hwCodecPredicate = arg -> {
        final String name = arg.getName();

        for (String prefix : EXYNOS_DECODER_PREFIXES) {
            if (name.startsWith(prefix)) {
                return false;
            }
        }

        // Filter out the Google AV1 codec.
        return !name.startsWith(GOOGLE_AV1_DECODER);
    };
    private static final Predicate<MediaCodecInfo> swCodecPredicate = arg -> {
        // Noop, just making sure we can customize it easily if needed.
        return true;
    };

    /**
     * Create decoder factory using default hardware decoder factory.
     */
    public JitsiVideoDecoderFactory(@Nullable EglBase.Context eglContext) {
        this.hardwareVideoDecoderFactory = new HardwareVideoDecoderFactory(eglContext, hwCodecPredicate);
        this.platformSoftwareVideoDecoderFactory = new JitsiPlatformVideoDecoderFactory(eglContext, swCodecPredicate);
    }

    @Override
    public @Nullable VideoDecoder createDecoder(VideoCodecInfo codecType) {
        VideoDecoder softwareDecoder = softwareVideoDecoderFactory.createDecoder(codecType);
        final VideoDecoder hardwareDecoder = hardwareVideoDecoderFactory.createDecoder(codecType);
        if (softwareDecoder == null) {
            softwareDecoder = platformSoftwareVideoDecoderFactory.createDecoder(codecType);
        }
        if (hardwareDecoder != null && softwareDecoder != null) {
            // Both hardware and software supported, wrap it in a software fallback
            return new VideoDecoderFallback(
                /* fallback= */ softwareDecoder, /* primary= */ hardwareDecoder);
        }
        return hardwareDecoder != null ? hardwareDecoder : softwareDecoder;
    }

    @Override
    public VideoCodecInfo[] getSupportedCodecs() {
        LinkedHashSet<VideoCodecInfo> supportedCodecInfos = new LinkedHashSet<>();

        supportedCodecInfos.addAll(Arrays.asList(softwareVideoDecoderFactory.getSupportedCodecs()));
        supportedCodecInfos.addAll(Arrays.asList(hardwareVideoDecoderFactory.getSupportedCodecs()));
        supportedCodecInfos.addAll(Arrays.asList(platformSoftwareVideoDecoderFactory.getSupportedCodecs()));

        return supportedCodecInfos.toArray(new VideoCodecInfo[supportedCodecInfos.size()]);
    }
}
