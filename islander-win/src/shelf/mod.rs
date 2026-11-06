// shelf/mod.rs — Temporary file shelf (drag-and-drop onto the island)

use std::path::{Path, PathBuf};
use uuid::Uuid;

pub const MAX_FILE_BYTES: u64 = 10_000_000;
pub const MAX_TOTAL_BYTES: u64 = 100_000_000;

#[derive(Debug, Clone)]
pub struct ShelfItem {
    pub id: Uuid,
    pub url: PathBuf,
    pub name: String,
    pub size: u64,
    pub added_at: std::time::Instant,
}

pub struct ShelfStore {
    pub items: Vec<ShelfItem>,
    pub message: Option<(String, std::time::Instant)>, // text + expiry
    directory: PathBuf,
    reserved: u64,
}

impl ShelfStore {
    pub fn new() -> Self {
        let dir = std::env::temp_dir().join("IslanderShelf");
        // Remove leftovers from a previous run.
        let _ = std::fs::remove_dir_all(&dir);
        Self {
            items: Vec::new(),
            message: None,
            directory: dir,
            reserved: 0,
        }
    }

    pub fn total_size(&self) -> u64 {
        self.items.iter().map(|i| i.size).sum()
    }

    /// Add a file from a path (e.g. from a drop event).
    pub fn add_file(&mut self, source: &Path) {
        let meta = match std::fs::metadata(source) {
            Ok(m) => m,
            Err(e) => {
                self.show_message(format!("Could not read file: {e}"));
                return;
            }
        };
        let name = source
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "file".into());

        if meta.is_dir() {
            self.show_message(format!(
                "{name} is a folder. Only files can go on the shelf."
            ));
            return;
        }
        let size = meta.len();
        if !self.accepts(size, &name) {
            return;
        }

        let id = Uuid::new_v4();
        let dest_dir = self.directory.join(id.to_string());
        let dest = dest_dir.join(&name);
        if let Err(e) = std::fs::create_dir_all(&dest_dir) {
            self.show_message(format!("Could not create shelf folder: {e}"));
            return;
        }
        if let Err(e) = std::fs::copy(source, &dest) {
            let _ = std::fs::remove_dir_all(&dest_dir);
            self.show_message(format!("Could not copy {name}: {e}"));
            return;
        }
        self.items.insert(
            0,
            ShelfItem {
                id,
                url: dest,
                name,
                size,
                added_at: std::time::Instant::now(),
            },
        );
    }

    fn accepts(&mut self, size: u64, name: &str) -> bool {
        if size > MAX_FILE_BYTES {
            self.show_message_imm(format!(
                "{name} is {}. The limit is 10 MB per file.",
                format_bytes(size)
            ));
            return false;
        }
        if self.total_size() + self.reserved + size > MAX_TOTAL_BYTES {
            self.show_message_imm("The shelf is full (100 MB). Clean it to add more.".into());
            return false;
        }
        true
    }

    pub fn open(&self, item: &ShelfItem) {
        #[cfg(windows)]
        {
            use std::os::windows::ffi::OsStrExt;
            let wide: Vec<u16> = item
                .url
                .as_os_str()
                .encode_wide()
                .chain(std::iter::once(0))
                .collect();
            unsafe {
                windows::Win32::UI::Shell::ShellExecuteW(
                    None,
                    windows::core::w!("open"),
                    windows::core::PCWSTR(wide.as_ptr()),
                    None,
                    None,
                    windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL,
                );
            }
        }
        #[cfg(not(windows))]
        let _ = std::process::Command::new("open").arg(&item.url).spawn();
    }

    pub fn copy_to_clipboard(&mut self, item: &ShelfItem) {
        #[cfg(windows)]
        clipboard_copy_file(&item.url);
        self.show_message(format!("Copied {}", item.name));
    }

    pub fn remove(&mut self, id: Uuid) {
        self.items.retain(|i| i.id != id);
        let dir = self.directory.join(id.to_string());
        let _ = std::fs::remove_dir_all(dir);
    }

    pub fn clean(&mut self) {
        let _ = std::fs::remove_dir_all(&self.directory);
        self.items.clear();
    }

    pub fn tick_message(&mut self) {
        if let Some((_, exp)) = &self.message {
            if exp.elapsed().as_secs_f32() > 4.0 {
                self.message = None;
            }
        }
    }

    fn show_message(&self, text: String) {
        // Can't take &mut self here from accepts(); call show_message_imm from public methods.
        // This is a convenience alias.
        unsafe {
            let this = self as *const Self as *mut Self;
            (*this).show_message_imm(text);
        }
    }

    fn show_message_imm(&mut self, text: String) {
        self.message = Some((text, std::time::Instant::now()));
    }
}

pub fn format_bytes(bytes: u64) -> String {
    if bytes >= 1_000_000 {
        format!("{:.1} MB", bytes as f64 / 1_000_000.0)
    } else if bytes >= 1_000 {
        format!("{:.0} KB", bytes as f64 / 1_000.0)
    } else {
        format!("{bytes} B")
    }
}

#[cfg(windows)]
fn clipboard_copy_file(path: &Path) {
    use std::os::windows::ffi::OsStrExt;
    use windows::Win32::System::DataExchange::{
        CloseClipboard, EmptyClipboard, OpenClipboard, SetClipboardData,
    };
    use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};

    // Build DROPFILES structure + null-terminated wide path + double-null terminator.
    let wide: Vec<u16> = path.as_os_str().encode_wide().chain([0u16, 0u16]).collect();
    // DROPFILES: pFiles offset, pt (unused), fNC, fWide
    let header_size = 20usize;
    let data_size = header_size + wide.len() * 2;

    unsafe {
        let hmem = match GlobalAlloc(GMEM_MOVEABLE, data_size) {
            Ok(h) => h,
            Err(_) => return,
        };
        let ptr = GlobalLock(hmem) as *mut u8;
        if ptr.is_null() {
            let _ = GlobalUnlock(hmem);
            return;
        }

        // Write DROPFILES header (pFiles = 20, pt = {0,0}, fNC = 0, fWide = 1)
        let header: [u32; 5] = [header_size as u32, 0, 0, 0, 1];
        std::ptr::copy_nonoverlapping(header.as_ptr() as *const u8, ptr, header_size);
        // Write wide file path.
        let dst = ptr.add(header_size) as *mut u16;
        std::ptr::copy_nonoverlapping(wide.as_ptr(), dst, wide.len());
        let _ = GlobalUnlock(hmem);

        if OpenClipboard(None).is_ok() {
            let _ = EmptyClipboard();
            // CF_HDROP = 15
            let _ = SetClipboardData(15, windows::Win32::Foundation::HANDLE(hmem.0));
            let _ = CloseClipboard();
        }
    }
}
