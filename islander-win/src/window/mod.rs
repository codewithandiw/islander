// window/mod.rs — Windows-specific window helpers (positioning, hit-testing, session)

use eframe::egui::Pos2;

#[cfg(windows)]
use windows::Win32::Foundation::{HWND, POINT, RECT};

#[cfg(windows)]
pub fn get_islander_hwnd() -> Option<HWND> {
    use windows::core::w;
    use windows::Win32::UI::WindowsAndMessaging::FindWindowW;
    unsafe {
        match FindWindowW(None, w!("Islander")) {
            Ok(h) if !h.0.is_null() => Some(h),
            _ => None,
        }
    }
}

/// Center the Islander window at the top of the primary monitor in physical pixels.
#[cfg(windows)]
pub fn center_window_top(hwnd: HWND) -> bool {
    use windows::Win32::UI::WindowsAndMessaging::{
        GetSystemMetrics, GetWindowRect, SetWindowPos, HWND_TOPMOST,
        SM_CXSCREEN, SWP_NOACTIVATE, SWP_NOSIZE,
    };
    unsafe {
        let mut rect = RECT::default();
        if GetWindowRect(hwnd, &mut rect).is_ok() {
            let win_w = rect.right - rect.left;
            let screen_w = GetSystemMetrics(SM_CXSCREEN);
            let x = (screen_w - win_w) / 2;
            let _ = SetWindowPos(
                hwnd,
                HWND_TOPMOST,
                x,
                0,
                0,
                0,
                SWP_NOSIZE | SWP_NOACTIVATE,
            );
            true
        } else {
            false
        }
    }
}

#[cfg(not(windows))]
pub fn center_window_top(_: ()) -> bool {
    true
}

/// Get the physical screen coordinates of the cursor globally.
#[cfg(windows)]
pub fn get_cursor_screen_pos() -> Option<(i32, i32)> {
    use windows::Win32::UI::WindowsAndMessaging::GetCursorPos;
    unsafe {
        let mut pt = POINT::default();
        if GetCursorPos(&mut pt).is_ok() {
            Some((pt.x, pt.y))
        } else {
            None
        }
    }
}

#[cfg(not(windows))]
pub fn get_cursor_screen_pos() -> Option<(i32, i32)> {
    None
}

/// Get the current window bounding rect in physical screen coordinates.
#[cfg(windows)]
pub fn get_window_rect(hwnd: HWND) -> Option<RECT> {
    use windows::Win32::UI::WindowsAndMessaging::GetWindowRect;
    unsafe {
        let mut rect = RECT::default();
        if GetWindowRect(hwnd, &mut rect).is_ok() {
            Some(rect)
        } else {
            None
        }
    }
}

#[cfg(not(windows))]
pub fn get_window_rect(_: ()) -> Option<()> {
    None
}

/// Estimate the initial (x, y) logical position to center at top of screen before HWND is ready.
pub fn get_initial_top_center_pos(win_logical_width: f32) -> Pos2 {
    #[cfg(windows)]
    {
        use windows::Win32::UI::WindowsAndMessaging::{GetSystemMetrics, SM_CXSCREEN};
        unsafe {
            let screen_w = GetSystemMetrics(SM_CXSCREEN) as f32;
            // Default 96 DPI fallback for initial estimation
            let x = ((screen_w - win_logical_width) / 2.0).max(0.0);
            Pos2::new(x, 0.0)
        }
    }
    #[cfg(not(windows))]
    {
        Pos2::new(0.0, 0.0)
    }
}

#[cfg(windows)]
unsafe extern "system" fn islander_subclass_proc(
    hwnd: HWND,
    msg: u32,
    wparam: windows::Win32::Foundation::WPARAM,
    lparam: windows::Win32::Foundation::LPARAM,
    _uidsubclass: usize,
    _refdata: usize,
) -> windows::Win32::Foundation::LRESULT {
    const WM_POWERBROADCAST: u32 = 0x0218;
    const WM_WTSSESSION_CHANGE: u32 = 0x02B1;
    const PBT_APMSUSPEND: u32 = 0x0004;
    const PBT_APMRESUMESUSPEND: u32 = 0x0007;
    const PBT_APMRESUMEAUTOMATIC: u32 = 0x0012;
    const WTS_SESSION_LOCK: u32 = 0x7;
    const WTS_SESSION_UNLOCK: u32 = 0x8;

    match msg {
        WM_POWERBROADCAST => match wparam.0 as u32 {
            PBT_APMSUSPEND => crate::focus::activity::set_system_asleep(true),
            PBT_APMRESUMESUSPEND | PBT_APMRESUMEAUTOMATIC => {
                crate::focus::activity::set_system_asleep(false)
            }
            _ => {}
        },
        WM_WTSSESSION_CHANGE => match wparam.0 as u32 {
            WTS_SESSION_LOCK => crate::focus::activity::set_screen_locked(true),
            WTS_SESSION_UNLOCK => crate::focus::activity::set_screen_locked(false),
            _ => {}
        },
        _ => {}
    }

    windows::Win32::UI::Shell::DefSubclassProc(hwnd, msg, wparam, lparam)
}

#[cfg(windows)]
pub fn register_session_notifications(hwnd: HWND) {
    use windows::Win32::System::RemoteDesktop::{
        WTSRegisterSessionNotification, NOTIFY_FOR_THIS_SESSION,
    };
    use windows::Win32::UI::Shell::SetWindowSubclass;
    unsafe {
        let _ = WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION);
        let _ = SetWindowSubclass(hwnd, Some(islander_subclass_proc), 101, 0);
    }
}

#[cfg(not(windows))]
pub fn register_session_notifications(_: ()) {}
