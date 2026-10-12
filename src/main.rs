#[macro_use]
extern crate anyhow;
extern crate lz_fear;

use anyhow::{Context, Result};
use clap::Parser;
use lz_fear::CompressionSettings;

#[cfg(feature = "cursor")]
use libremarkable::cgmath;
#[cfg(feature = "cursor")]
use libremarkable::input::{ev::EvDevContext, InputDevice, InputEvent, WacomEvent, WacomPen};

use std::default::Default;
use std::fs::File;
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::net::{TcpListener, TcpStream};
use std::process::Command;
use std::sync::mpsc::channel;
#[cfg(feature = "cursor")]
use std::sync::mpsc::Receiver;
use std::thread;
use std::time::Duration;

#[derive(Parser, Debug)]
#[command(author, version)]
pub struct Opts {
    /// Listen for an (unsecure) TCP connection to send the data to which reduces some load on the reMarkable and improves fps.
    #[arg(long, name = "port", short = 'l')]
    listen: Option<usize>,

    /// Height (in pixels) of the framebuffer.
    #[arg(long, name = "height", short = 'h')]
    height: usize,

    /// Width (in pixels) of the framebuffer.
    #[arg(long, name = "width", short = 'w')]
    width: usize,

    /// How many bytes represent one pixel in the framebuffer.
    #[arg(long, name = "bytes", short = 'b')]
    bytes_per_pixel: usize,

    /// File containing the framebuffer data. If this equals the string ':mem:' it will try to read the framebuffer from xochitl's process memory.
    #[arg(long, name = "path", short = 'f')]
    file: String,

    /// Show a cursor where the pen is hovering. Requires building with --features cursor.
    #[arg(long, name = "cursor", short = 'c')]
    show_cursor: bool,

    /// Memory offset
    #[arg(long, name = "skip", short = 's')]
    skip: usize,
}

fn main() -> Result<()> {
    let ref opts: Opts = Opts::parse();

    if opts.show_cursor && !cfg!(feature = "cursor") {
        eprintln!("Warning: cursor support requires building with --features cursor.");
    }

    let (file, offset) = if opts.file == ":mem:" {
        let pid = xochitl_pid()?;
        let offset = fb_offset(pid, opts.skip)?;
        let mem = format!("/proc/{}/mem", pid);
        (mem, offset)
    } else {
        (opts.file.to_owned(), 0)
    };

    let streamer = ReStreamer::init(
        &file,
        offset,
        opts.width,
        opts.height,
        opts.bytes_per_pixel,
        opts.show_cursor,
    )?;

    let stdout = std::io::stdout();
    let data_target: Box<dyn Write> = if let Some(port) = opts.listen {
        Box::new(listen_timeout(port, Duration::from_secs(3))?)
    } else {
        Box::new(stdout.lock())
    };

    let lz4: CompressionSettings = Default::default();
    lz4.compress(streamer, data_target)
        .context("Error while compressing framebuffer stream")
}

fn listen_timeout(port: usize, timeout: Duration) -> Result<TcpStream> {
    let listen_addr = format!("0.0.0.0:{}", port);
    let listen = TcpListener::bind(&listen_addr)?;
    eprintln!("[rM] listening for a TCP connection on {}", listen_addr);

    let (tx, rx) = channel();
    thread::spawn(move || {
        tx.send(listen.accept()).unwrap();
    });

    let (conn, conn_addr) = rx
        .recv_timeout(timeout)
        .context("Timeout while waiting for host to connect to reMarkable")??;
    eprintln!("[rM] connection received from {}", conn_addr);
    conn.set_write_timeout(Some(timeout))?;
    Ok(conn)
}

fn xochitl_pid() -> Result<usize> {
    let output = Command::new("/bin/pidof")
        .args(&["xochitl"])
        .output()
        .context("Failed to run `/bin/pidof xochitl`")?;
    if output.status.success() {
        let pid = &output.stdout;
        let pid_str = std::str::from_utf8(pid)?.trim();
        pid_str
            .parse()
            .with_context(|| format!("Failed to parse xochitl's pid: {}", pid_str))
    } else {
        Err(anyhow!(
            "Could not find pid of xochitl, is xochitl running?"
        ))
    }
}

fn fb_offset(pid: usize, skip: usize) -> Result<usize> {
    let file = File::open(format!("/proc/{}/maps", &pid))?;
    let lines: Vec<String> = BufReader::new(file)
        .lines()
        .collect::<std::io::Result<_>>()?;

    // rM1: framebuffer is the mapping immediately after /dev/fb0
    if let Some(pos) = lines.iter().position(|l| l.ends_with("/dev/fb0")) {
        let line = lines.get(pos + 1)
            .with_context(|| format!("No line after /dev/fb0 in /proc/{}/maps", pid))?;
        let addr = line.split("-").next()
            .with_context(|| format!("Error parsing line in /proc/{}/maps", pid))?;
        let address = usize::from_str_radix(addr, 16)
            .context("Error parsing framebuffer address")?;
        return Ok(address + skip);
    }

    // rM2 / Tatsu / Paper Pure: the BGRA color rendering buffer sits immediately
    // after the last /dev/dri/card0 DRM waveform buffer. It is an anonymous
    // rw-p mapping of ~10–16 MB.
    if let Some(drm_last) = lines.iter().filter(|l| l.contains("/dev/dri/card0")).last() {
        let drm_hi = drm_last.split('-').nth(1)
            .and_then(|s| s.split_whitespace().next())
            .and_then(|s| usize::from_str_radix(s, 16).ok())
            .unwrap_or(0);

        if let Some(line) = lines.iter().find(|l| {
            let parts: Vec<&str> = l.split_whitespace().collect();
            if parts.len() != 5 { return false; }
            if let (Some(lo_s), Some(hi_s)) = (parts[0].split('-').next(), parts[0].split('-').nth(1)) {
                if let (Ok(lo), Ok(hi)) = (usize::from_str_radix(lo_s, 16), usize::from_str_radix(hi_s, 16)) {
                    return lo >= drm_hi && (hi - lo) >= 10*1024*1024 && (hi - lo) <= 16*1024*1024;
                }
            }
            false
        }) {
            let addr = line.split('-').next()
                .context("Error parsing color buffer address")?;
            let address = usize::from_str_radix(addr, 16)
                .context("Error parsing color buffer address")?;
            eprintln!("[rM] Color buffer at {:#x}", address);
            return Ok(address + skip);
        }
    }

    Err(anyhow!("No framebuffer mapping found in /proc/{}/maps", pid))
}

pub struct ReStreamer {
    file: File,
    start: u64,
    cursor: usize,
    size: usize,

    #[cfg(feature = "cursor")]
    show_cursor: bool,
    #[cfg(feature = "cursor")]
    width: usize,
    #[cfg(feature = "cursor")]
    height: usize,
    #[cfg(feature = "cursor")]
    bytes_per_pixel: usize,
    #[cfg(feature = "cursor")]
    input_rx: Receiver<InputEvent>,
    #[cfg(feature = "cursor")]
    pen_pos: Option<(usize, usize)>,
    #[cfg(feature = "cursor")]
    drawing: bool,
}

impl ReStreamer {
    pub fn init(
        path: &str,
        offset: usize,
        width: usize,
        height: usize,
        bytes_per_pixel: usize,
        show_cursor: bool,
    ) -> Result<ReStreamer> {
        let start = offset as u64;
        let size = width * height * bytes_per_pixel;
        let cursor = 0;
        let file = File::open(path)?;

        #[cfg(feature = "cursor")]
        let (input_tx, input_rx) = channel::<InputEvent>();
        #[cfg(feature = "cursor")]
        if show_cursor {
            EvDevContext::new(InputDevice::Wacom, input_tx).start();
        }

        #[cfg(not(feature = "cursor"))]
        let _ = (width, height, bytes_per_pixel, show_cursor);

        let mut streamer = ReStreamer {
            file,
            start: start,
            cursor,
            size,
            #[cfg(feature = "cursor")]
            show_cursor,
            #[cfg(feature = "cursor")]
            width,
            #[cfg(feature = "cursor")]
            height,
            #[cfg(feature = "cursor")]
            bytes_per_pixel,
            #[cfg(feature = "cursor")]
            input_rx,
            #[cfg(feature = "cursor")]
            pen_pos: None,
            #[cfg(feature = "cursor")]
            drawing: false,
        };
        streamer.next_frame()?;
        Ok(streamer)
    }

    pub fn next_frame(&mut self) -> std::io::Result<()> {
        self.file.seek(SeekFrom::Start(self.start))?;
        self.cursor = 0;
        #[cfg(feature = "cursor")]
        if self.show_cursor {
            self.read_input();
        }

        Ok(())
    }

    /// Read input events to figure out pen state and position.
    #[cfg(feature = "cursor")]
    fn read_input(&mut self) {
        let mut down = self.pen_pos.is_some();
        let mut pos = self.pen_pos.unwrap_or((0, 0));
        while let Ok(event) = self.input_rx.try_recv() {
            match event {
                InputEvent::WacomEvent { event: e } => match e {
                    WacomEvent::InstrumentChange {
                        pen: WacomPen::ToolPen,
                        state: s,
                    } => {
                        down = s;
                    }
                    WacomEvent::Hover {
                        position: cgmath::Point2 { x, y },
                        ..
                    } => {
                        pos = (x as usize, y as usize);
                        self.drawing = false;
                    }
                    WacomEvent::Draw { .. } => {
                        // no need to show position while drawing
                        self.drawing = true;
                    }
                    _ => (),
                },
                _ => (),
            }
        }

        self.pen_pos = if down { Some(pos) } else { None };
    }

    /// Draw pen position into fb data, if necessary (in hover range and not drawing).
    #[cfg(feature = "cursor")]
    fn draw_pen_position(&mut self, buf: &mut [u8]) {
        if let (false, Some((y, x))) = (self.drawing, self.pen_pos) {
            let flip = self.width > self.height;
            let (x, y) = if flip { (y, x) } else { (x, y) };
            // we need negative numbers to calculate offsets correctly
            let width = if flip { self.height } else { self.width } as isize;
            let height = if flip { self.width } else { self.height } as isize;
            let bpp = self.bytes_per_pixel as isize;
            let cursor = self.cursor as isize;
            for (i, (yoff, no)) in PEN_IMAGE.iter().enumerate() {
                // we draw vertically (lines along y)
                let xoff = i as isize - (PEN_IMAGE.len() as isize / 2);
                let xstart = x as isize + xoff;
                // line outside of canvas?
                if xstart < 0 || xstart >= width {
                    continue;
                }
                let mut ystart = (height - y as isize) + yoff;
                let mut no = *no;
                // cut-off at sides
                if ystart < 0 {
                    no += ystart;
                    ystart = 0;
                }
                if ystart + no > height {
                    no = height - ystart;
                }
                if no <= 0 {
                    continue;
                }
                // translate to buf indexes, check bounds and draw
                let mut px_start = (xstart * height + ystart) * bpp;
                let mut px_end = px_start + no * bpp;
                // outside current buf?
                if px_end < cursor || px_start >= cursor + buf.len() as isize {
                    continue;
                }
                // truncate if partially outside
                if px_start < cursor {
                    px_start = cursor;
                }
                if px_end > cursor + buf.len() as isize {
                    px_end = cursor + buf.len() as isize;
                }
                // invert pixel (on RM2)
                // TODO: Do something sensible on RM1
                for b in buf[(px_start - cursor) as usize..(px_end - cursor) as usize].iter_mut() {
                    *b = 255 - *b;
                }
            }
        }
    }
}

// Image of pen, given as (offset from pen position, number of pixels)
#[cfg(feature = "cursor")]
static PEN_IMAGE: [(isize, isize); 17] = [
    (0, 1),   // 00000000100000000
    (0, 1),   // 00000000100000000
    (0, 1),   // 00000000100000000
    (-1, 3),  // 00000001110000000
    (-3, 7),  // 00000111111100000
    (-4, 9),  // 00001111111110000
    (-4, 9),  // 00001111111110000
    (-5, 11), // 00011111111111000
    (-8, 17), // 11111111111111111
    (-5, 11), // 00011111111111000
    (-4, 9),  // 00001111111110000
    (-4, 9),  // 00001111111110000
    (-3, 7),  // 00000111111100000
    (-1, 3),  // 00000001110000000
    (0, 1),   // 00000000100000000
    (0, 1),   // 00000000100000000
    (0, 1),   // 00000000100000000
];

impl Read for ReStreamer {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let requested = buf.len();
        let bytes_read = if self.cursor + requested < self.size {
            self.file.read(buf)?
        } else {
            let rest = self.size - self.cursor;
            self.file.read(&mut buf[0..rest])?
        };

        #[cfg(feature = "cursor")]
        if self.show_cursor {
            self.draw_pen_position(&mut buf[0..bytes_read]);
        }

        self.cursor += bytes_read;
        if self.cursor == self.size {
            self.next_frame()?;
        }
        Ok(bytes_read)
    }
}

