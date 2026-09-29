//! One-time, USB-only setup. Never logs pairing keys and never overwrites a record.
use idevice::{IdeviceService, core_device_proxy::CoreDeviceProxy, rsd::RsdHandshake,
    RemoteXpcClient, remote_pairing::{RemotePairingClient,RpPairingFile},
    usbmuxd::{UsbmuxdAddr,Connection}};
use std::{path::Path,fs::OpenOptions,os::unix::fs::OpenOptionsExt,time::Duration};

#[tokio::main]
async fn main(){
    let args:Vec<String>=std::env::args().collect();
    if args.len()!=3{eprintln!("usage: linedraw-pair-usb UDID OUTPUT");std::process::exit(2)}
    if Path::new(&args[2]).exists(){eprintln!("Output exists; refusing overwrite");std::process::exit(2)}
    match tokio::time::timeout(Duration::from_secs(90),pair(&args[1],&args[2])).await{
        Ok(Ok(()))=>println!("Remote Pairing record created with mode 0600."),
        Ok(Err(stage))=>{eprintln!("Setup failed: {stage}");std::process::exit(1)},
        Err(_)=>{eprintln!("Setup timed out");std::process::exit(1)}
    }
}
async fn pair(udid:&str,output:&str)->Result<(),&'static str>{
    let addr=UsbmuxdAddr::UnixSocket("/var/run/usbmuxd".into());
    let mut mux=addr.connect(73).await.map_err(|_|"USB_CONNECT")?;
    let device=mux.get_devices().await.map_err(|_|"USB_LIST")?.into_iter()
        .find(|d|d.udid==udid && matches!(d.connection_type,Connection::Usb)).ok_or("USB_DEVICE_MISSING")?;
    let provider=device.to_provider(addr,"LineDraw-first-setup");
    println!("Opening trusted USB developer tunnel");
    let proxy=CoreDeviceProxy::connect(&provider).await.map_err(|_|"USB_PROXY")?;
    let port=proxy.tunnel_info().server_rsd_port;
    let mut adapter=proxy.create_software_tunnel().map_err(|_|"USB_TUNNEL")?.to_async_handle();
    let stream=adapter.connect(port).await.map_err(|_|"RSD_CONNECT")?;
    let rsd=RsdHandshake::new(stream).await.map_err(|_|"RSD_HANDSHAKE")?;
    let port=rsd.services.get("com.apple.internal.dt.coredevice.untrusted.tunnelservice").ok_or("PAIRING_SERVICE_MISSING")?.port;
    let stream=adapter.connect(port).await.map_err(|_|"PAIRING_CONNECT")?;
    let mut xpc=RemoteXpcClient::new(stream).await.map_err(|_|"PAIRING_XPC")?;
    xpc.do_handshake().await.map_err(|_|"PAIRING_HANDSHAKE")?;
    xpc.recv_root().await.map_err(|_|"PAIRING_GREETING")?;
    // A unique host name avoids replacing another tool's device-side trust entry.
    let host=format!("LineDraw-{}",std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs());
    let mut record=RpPairingFile::generate(&host);
    let mut rpc=RemotePairingClient::new(xpc,&host);
    println!("Requesting Remote Pairing through the trusted USB connection");
    rpc.connect(&mut record,async || "000000".to_owned()).await.map_err(|_|"REMOTE_PAIRING")?;
    let mut file=OpenOptions::new().write(true).create_new(true).mode(0o600).open(output).map_err(|_|"PRIVATE_FILE_CREATE")?;
    let mut plist:plist::Dictionary=plist::from_bytes(&record.to_bytes()).map_err(|_|"ENCODE")?;
    plist.insert("LineDrawDeviceUDID".into(),udid.into());
    plist::to_writer_xml(&mut file,&plist).map_err(|_|"PRIVATE_FILE_WRITE")?;
    file.sync_all().map_err(|_|"PRIVATE_FILE_SYNC")?;
    Ok(())
}
