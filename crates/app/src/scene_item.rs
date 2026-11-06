//! The editor viewport: a QQuickPaintedItem that blits the core renderer's pixels. No JS, no canvas API.
use crate::backend::ed;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qrect.h");
        type QRect = cxx_qt_lib::QRect;
        include!("cxx-qt-lib/qsizef.h");
        type QSizeF = cxx_qt_lib::QSizeF;
        include!("cxx-qt-lib/qpainter.h");
        type QPainter = cxx_qt_lib::QPainter;
    }
    unsafe extern "C++" {
        include!(<QtQuick/QQuickPaintedItem>);
        type QQuickPaintedItem;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[base = QQuickPaintedItem]
        type SceneItem = super::SceneItemRust;

        #[qinvokable]
        #[cxx_override]
        unsafe fn paint(self: Pin<&mut Self>, painter: *mut QPainter);

        #[inherit]
        fn size(self: &Self) -> QSizeF;
        #[inherit]
        fn update(self: Pin<&mut Self>);

        /// kind: 0 down, 1 move, 2 up, 3 wheel, 4 fit, 5 actual size, 6 repaint, 7 space down, 8 space up
        /// flags: 1 ctrl, 2 shift, 4 alt, 8 middle button
        #[qinvokable]
        fn input(self: Pin<&mut Self>, kind: i32, x: f64, y: f64, a: f64, b: f64, flags: i32);
        #[qinvokable]
        fn key(self: Pin<&mut Self>, name: &QString, flags: i32);
        #[qinvokable]
        #[cxx_name = "zoomPercent"]
        fn zoom_percent(self: &Self) -> i32;

        #[qsignal]
        fn edited(self: Pin<&mut Self>);
    }
}

use core::pin::Pin;
use cxx_qt_lib::{QImage, QImageFormat, QRect, QString};

#[derive(Default)]
pub struct SceneItemRust {}

extern "C" fn no_cleanup(_: *mut cxx_qt_lib::c_void) {}

impl qobject::SceneItem {
    /// # Safety
    /// `painter` is provided by Qt and valid for the duration of the call.
    pub unsafe fn paint(mut self: Pin<&mut Self>, painter: *mut qobject::QPainter) {
        let Some(painter) = painter.as_mut() else { return };
        let size = self.as_ref().size();
        let (w, h) = (size.width().max(1.0) as u32, size.height().max(1.0) as u32);
        let mut editor = ed();
        if let Some((px, w, h)) = editor.render_view(w, h) {
            // tiny-skia produces premultiplied RGBA8, exactly Qt's Format_RGBA8888_Premultiplied.
            let img = QImage::from_raw_parts(px.as_ptr(), w as i32, h as i32, QImageFormat::Format_RGBA8888_Premultiplied, no_cleanup, std::ptr::null_mut());
            Pin::new_unchecked(painter).draw_image(&QRect::new(0, 0, w as i32, h as i32), &img);
        }
        let _ = self.as_mut();
    }

    pub fn input(mut self: Pin<&mut Self>, kind: i32, x: f64, y: f64, a: f64, b: f64, flags: i32) {
        let size = self.as_ref().size();
        let changed = {
            let mut e = ed();
            match kind {
                0 => { e.pointer_down(x, y, flags & 8 != 0); true }
                1 => e.pointer_move(x, y, flags & 4 != 0),
                2 => e.pointer_up(),
                3 => { e.wheel(a, b, flags & 1 != 0, x, y); false }
                4 => { e.fit(size.width() as u32, size.height() as u32); false }
                5 => { e.actual_size(); false }
                7 => { e.space = true; false }
                8 => { e.space = false; false }
                _ => false,
            }
        };
        self.as_mut().update();
        if changed || kind == 0 { self.as_mut().edited(); }
    }

    pub fn key(mut self: Pin<&mut Self>, name: &QString, flags: i32) {
        let changed = ed().key(&name.to_string(), flags & 1 != 0, flags & 2 != 0);
        self.as_mut().update();
        if changed { self.as_mut().edited(); }
    }

    pub fn zoom_percent(&self) -> i32 { (ed().zoom() * 100.0).round() as i32 }
}
