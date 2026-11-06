// visualizer/mod.rs — WASAPI loopback capture → FFT → 24 log-spaced bands

use parking_lot::RwLock;
use rustfft::{num_complex::Complex, FftPlanner};
use std::sync::Arc;

use crate::now_playing::NowPlayingState;
use crate::settings::AppSettings;

pub const BAND_COUNT: usize = 24;

#[derive(Debug, Default, Clone)]
pub struct AudioSpectrum {
    pub bands: [f32; BAND_COUNT],
    pub level: f32,
    active: bool,
}

impl AudioSpectrum {
    pub fn set_active(&mut self, active: bool) {
        self.active = active;
        if !active {
            self.bands = [0.0; BAND_COUNT];
            self.level = 0.0;
        }
    }

    pub fn is_active(&self) -> bool {
        self.active
    }
}

/// Background task: runs WASAPI loopback when music is playing + visualizer enabled.
pub async fn run_wasapi_loopback(
    spectrum: Arc<RwLock<AudioSpectrum>>,
    settings: Arc<RwLock<AppSettings>>,
    now_playing: Arc<RwLock<NowPlayingState>>,
) {
    loop {
        let should_run = {
            let np = now_playing.read();
            let s = settings.read();
            s.show_visualizer && np.current.as_ref().map(|c| c.is_playing).unwrap_or(false)
        };

        if should_run {
            spectrum.write().set_active(true);
            // Run capture on a blocking thread so we don't block the async executor.
            let spec_clone = Arc::clone(&spectrum);
            let settings_clone = Arc::clone(&settings);
            let np_clone = Arc::clone(&now_playing);

            tokio::task::spawn_blocking(move || {
                capture_loop(spec_clone, settings_clone, np_clone);
            })
            .await
            .ok();
        } else {
            spectrum.write().set_active(false);
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }
    }
}

#[cfg(windows)]
fn capture_loop(
    spectrum: Arc<RwLock<AudioSpectrum>>,
    settings: Arc<RwLock<AppSettings>>,
    now_playing: Arc<RwLock<NowPlayingState>>,
) {
    use windows::Win32::Media::Audio::*;
    use windows::Win32::System::Com::*;

    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);

        let enumerator: IMMDeviceEnumerator =
            match CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) {
                Ok(e) => e,
                Err(_) => return,
            };

        let device = match enumerator.GetDefaultAudioEndpoint(eRender, eConsole) {
            Ok(d) => d,
            Err(_) => return,
        };

        let client: IAudioClient = match device.Activate(CLSCTX_ALL, None) {
            Ok(c) => c,
            Err(_) => return,
        };

        let format_ptr = match client.GetMixFormat() {
            Ok(f) => f,
            Err(_) => return,
        };
        let format = &*format_ptr;
        let sample_rate = format.nSamplesPerSec as f64;
        let channels = format.nChannels as usize;

        let _ = client.Initialize(
            AUDCLNT_SHAREMODE_SHARED,
            AUDCLNT_STREAMFLAGS_LOOPBACK,
            10_000_000, // 1 second buffer
            0,
            format_ptr,
            None,
        );

        let capture_client: IAudioCaptureClient = match client.GetService() {
            Ok(c) => c,
            Err(_) => return,
        };

        let _ = client.Start();

        let mut analyzer = SpectrumAnalyzer::new(sample_rate);
        let interval = std::time::Duration::from_millis(10);

        loop {
            // Check if we should still be running.
            {
                let np = now_playing.read();
                let s = settings.read();
                let running =
                    s.show_visualizer && np.current.as_ref().map(|c| c.is_playing).unwrap_or(false);
                if !running {
                    break;
                }
            }

            let mut packet_length = match capture_client.GetNextPacketSize() {
                Ok(n) => n,
                Err(_) => break,
            };

            while packet_length > 0 {
                let mut data_ptr = std::ptr::null_mut();
                let mut frames = 0u32;
                let mut flags = 0u32;
                if capture_client
                    .GetBuffer(&mut data_ptr, &mut frames, &mut flags, None, None)
                    .is_err()
                {
                    break;
                }

                let samples: &[f32] =
                    std::slice::from_raw_parts(data_ptr as *const f32, frames as usize * channels);

                // Mix to mono.
                for frame in 0..frames as usize {
                    let mut sum = 0f32;
                    for ch in 0..channels {
                        sum += samples[frame * channels + ch];
                    }
                    analyzer.push(sum / channels as f32);
                }

                let _ = capture_client.ReleaseBuffer(frames);
                packet_length = match capture_client.GetNextPacketSize() {
                    Ok(n) => n,
                    Err(_) => break,
                };
            }

            if let Some((bands, level)) = analyzer.analyze() {
                let mut spec = spectrum.write();
                spec.bands = bands;
                spec.level = level;
            }

            std::thread::sleep(interval);
        }

        let _ = client.Stop();
        spectrum.write().set_active(false);
    }
}

#[cfg(not(windows))]
fn capture_loop(
    _spectrum: Arc<RwLock<AudioSpectrum>>,
    _settings: Arc<RwLock<AppSettings>>,
    _now_playing: Arc<RwLock<NowPlayingState>>,
) {
    // No-op on non-Windows.
}

// ── FFT analyzer ──────────────────────────────────────────────────────────────

struct SpectrumAnalyzer {
    fft_size: usize,
    planner: FftPlanner<f32>,
    window: Vec<f32>,
    samples: Vec<f32>,
    band_ranges: Vec<std::ops::Range<usize>>,
    last_publish: std::time::Instant,
    publish_interval: std::time::Duration,
}

impl SpectrumAnalyzer {
    fn new(sample_rate: f64) -> Self {
        let fft_size = 1024usize;
        let sr = if sample_rate > 0.0 {
            sample_rate
        } else {
            48_000.0
        };

        // Hanning window.
        let window: Vec<f32> = (0..fft_size)
            .map(|i| {
                0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / (fft_size - 1) as f32).cos())
            })
            .collect();

        // Log-spaced bands from 40 Hz to 16 kHz.
        let bin_width = sr / fft_size as f64;
        let max_bin = fft_size / 2 - 1;
        let mut band_ranges = Vec::with_capacity(BAND_COUNT);
        for i in 0..BAND_COUNT {
            let low = 40.0 * (16_000.0_f64 / 40.0).powf(i as f64 / BAND_COUNT as f64);
            let high = 40.0 * (16_000.0_f64 / 40.0).powf((i + 1) as f64 / BAND_COUNT as f64);
            let start = ((low / bin_width) as usize).clamp(1, max_bin);
            let end = ((high / bin_width) as usize).clamp(start + 1, max_bin + 1);
            band_ranges.push(start..end);
        }

        Self {
            fft_size,
            planner: FftPlanner::new(),
            window,
            samples: Vec::with_capacity(fft_size * 2),
            band_ranges,
            last_publish: std::time::Instant::now(),
            publish_interval: std::time::Duration::from_millis(33),
        }
    }

    fn push(&mut self, sample: f32) {
        self.samples.push(sample);
        if self.samples.len() > self.fft_size {
            self.samples.drain(0..self.samples.len() - self.fft_size);
        }
    }

    fn analyze(&mut self) -> Option<([f32; BAND_COUNT], f32)> {
        if self.samples.len() < self.fft_size {
            return None;
        }
        if self.last_publish.elapsed() < self.publish_interval {
            return None;
        }
        self.last_publish = std::time::Instant::now();

        let fft = self.planner.plan_fft_forward(self.fft_size);
        let mut buf: Vec<Complex<f32>> = self
            .samples
            .iter()
            .zip(&self.window)
            .map(|(&s, &w)| Complex { re: s * w, im: 0.0 })
            .collect();
        fft.process(&mut buf);

        let half = self.fft_size / 2;
        let magnitudes: Vec<f32> = buf[..half]
            .iter()
            .map(|c| c.norm() / self.fft_size as f32)
            .collect();

        let mut bands = [0f32; BAND_COUNT];
        for (i, range) in self.band_ranges.iter().enumerate() {
            let peak = magnitudes[range.clone()]
                .iter()
                .cloned()
                .fold(0f32, f32::max);
            let db = 20.0 * (peak + 1e-9).log10();
            bands[i] = ((db + 65.0) / 55.0).clamp(0.0, 1.0);
        }

        // RMS level.
        let rms = (self.samples.iter().map(|s| s * s).sum::<f32>() / self.fft_size as f32).sqrt();
        let level = ((20.0 * (rms + 1e-9).log10() + 50.0) / 44.0).clamp(0.0, 1.0);

        Some((bands, level))
    }
}
