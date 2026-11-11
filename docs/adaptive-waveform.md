# Adaptive waveform response

Compared with Eduannnn/quickshell-notch at the archived upstream commit recorded in PORTING.md: `notch/notch.qml` lines 266–306 configure six CAVA bars, 60 Hz output, automatic sensitivity, gain 1.4 and a noise gate. Lines 705–733 smooth their heights at roughly 60 Hz. This is a behavioral reference, not a claim to reproduce CAVA's FFT implementation.

The previous Swift mapping put RMS through a 66 dB scale. A tenfold amplitude change could only move the strongest bar by about 0.30 of its height range. It also published at 30 Hz. The replacement uses one adaptive peak reference shared across all bands, three-second reference decay, 25% headroom, a small silence threshold and an amplitude power curve. This preserves differences between frequency bands, allows quiet input to remain visible, and makes beats produce larger changes. Publishing is now 60 Hz with quick attack and release. No synthetic animation or per-band automatic gain is used.

Six AudioSpectrum tests passed, including a new alternating loud/quiet tone test requiring a drop exceeding 0.4, with quiet audio still visible and no saturation. Existing silence, nonfinite, frequency selection and stereo tests passed.
