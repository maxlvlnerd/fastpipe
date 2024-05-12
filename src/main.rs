use std::{fs::File, io::Read, path::PathBuf};

use clap::Parser;
use eyre::Result;
use libspa::pod::{serialize::PodSerializer, Pod};
use libspa_sys::{SPA_PARAM_EnumFormat, SPA_TYPE_OBJECT_Format};
use mimalloc::MiMalloc;
use pipewire::{
    keys::*,
    spa::Direction,
    stream::{Stream, StreamFlags},
    Context, MainLoop,
};

#[global_allocator]
static GLOBAL: MiMalloc = MiMalloc;

const CHANNELS: usize = 1;
const BUFFER_SIZE: usize = 1024 * 5;
const STRIDE: usize = std::mem::size_of::<i16>() * CHANNELS;
#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Args {
    file: PathBuf,
}
fn main() -> Result<()> {
    let args = Args::parse();
    let mut file = File::open(args.file)?;
    let mainloop = MainLoop::new()?;
    let context = Context::new(&mainloop)?;
    let core = context.connect(None)?;
    let (sender, reciver) = pipewire::channel::channel();
    std::thread::spawn(move || {
        let mut buffer = [0u8; BUFFER_SIZE];
        loop {
            file.read_exact(&mut buffer).unwrap();
            let _ = sender.send(buffer);
        }
    });

    let stream = Stream::new(
        &core,
        "fastpipe",
        pipewire::properties! {
            *MEDIA_TYPE => "Audio",
            *MEDIA_CLASS => "Audio/Source",
            *MEDIA_CATEGORY => "Playback",
            *MEDIA_ROLE => "Communication",
        },
    )?;
    let _idk = stream.add_local_listener_with_user_data(()).register()?;
    stream.connect(
        Direction::Output,
        None,
        StreamFlags::AUTOCONNECT | StreamFlags::MAP_BUFFERS,
        &mut [Pod::from_bytes(&create_params()).unwrap()],
    )?;
    let _rec = reciver.attach(&mainloop, move |snd_buffer| {
        if let Some(mut buffer) = stream.dequeue_buffer() {
            let datas = buffer.datas_mut();
            let data = &mut datas[0];
            let slice = data.data().unwrap();
            slice[0..BUFFER_SIZE].copy_from_slice(&snd_buffer);
            let chunk = data.chunk_mut();
            *chunk.offset_mut() = 0;
            *chunk.size_mut() = BUFFER_SIZE as u32;
            *chunk.stride_mut() = STRIDE as i32;
        }
    });
    mainloop.run();
    Ok(())
}

fn create_params<'a>() -> Vec<u8> {
    use libspa::param::audio::*;
    let mut audio_info = AudioInfoRaw::new();
    audio_info.set_format(AudioFormat::S16LE);
    audio_info.set_rate(44100);
    audio_info.set_channels(CHANNELS.try_into().unwrap());

    let values: Vec<u8> = PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &pipewire::spa::pod::Value::Object(pipewire::spa::pod::Object {
            type_: SPA_TYPE_OBJECT_Format,
            id: SPA_PARAM_EnumFormat,
            properties: audio_info.into(),
        }),
    )
    .unwrap()
    .0
    .into_inner();

    return values;
}
