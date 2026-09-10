//
//  NotchPulseGlareCue.swift
//  NotchPulse
//
//  Pixel-domain half of the gloss/glare cue (see `NotchPulseLivenessCues.glossGlare`);
//  no Vision/CoreImage import.
//  Populated by `NotchPulseGlareCueExtractor.extract(faceCrop:)`.
//  Ported from Glance's GlareCue.swift with NotchPulse naming.
//

import CoreGraphics

struct GlareSample: Equatable {
    /// Native pixel width of the measured crop; `renderCrop` only ever downsamples, so this
    /// is an honest detail measure — the cue confidence-weights down as it shrinks.
    let cropPixelWidth: CGFloat

    /// Fraction of crop pixels that are near-saturated and low-chroma — direct specular reflection.
    let specularFraction: Float

    /// How concentrated the specular pixels are into one region (densest 8x8 grid cell's
    /// share) vs. scattered — distinguishes glass glare from a shiny forehead.
    let specularClusterRatio: Float
}
