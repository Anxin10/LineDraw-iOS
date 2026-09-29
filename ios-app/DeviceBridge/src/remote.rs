//! On-device Remote Pairing transport. No LAN listener or automatic re-pairing.
use super::*;
use idevice::{RsdService,remote_pairing::{RpPairingFile,RpPairingSocket,RemotePairingClient,connect_tls_psk_tunnel_native},rsd::RsdHandshake};
use tokio::net::TcpStream;

pub struct Record { pub pair:RpPairingFile, pub udid:String }
pub fn parse(bytes:&[u8])->Option<Record>{
    let p:plist::Dictionary=plist::from_bytes(bytes).ok()?;
    let udid=p.get("LineDrawDeviceUDID")?.as_string()?.to_owned();
    if udid.is_empty() || udid.len()>64{return None}
    let pair=RpPairingFile::from_bytes(bytes).ok()?;
    if pair.e_private_key.verifying_key()!=pair.e_public_key || pair.identifier.is_empty(){return None}
    Some(Record{pair,udid})
}
async fn bounded<T>(seconds:u64,f:impl std::future::Future<Output=Result<T,idevice::IdeviceError>>,code:&'static str)->Result<T,&'static str>{
    tokio::time::timeout(Duration::from_secs(seconds),f).await.map_err(|_|code)?.map_err(|_|code)
}
async fn connect(record:&mut Record,state:&Arc<Mutex<Value>>)->Result<(idevice::tcp::handle::AdapterHandle,RsdHandshake,u16,RemotePairingClient<RpPairingSocket<TcpStream>>),&'static str>{
    set(&state,"connecting","RP_CONNECT");
    let stream=tokio::time::timeout(Duration::from_secs(12),TcpStream::connect(std::net::SocketAddr::from(([10,7,0,1],49152)))).await.map_err(|_|"RP_CONNECT_TIMEOUT")?.map_err(|_|"RP_CONNECT_FAILED")?;
    let mut rpc=RemotePairingClient::new(RpPairingSocket::new(stream),"LineDraw-device");
    set(&state,"connecting","RP_HANDSHAKE");
    bounded(12,rpc.attempt_pair_verify(),"RP_HANDSHAKE_FAILED").await?;
    // Verify only: no silent pair-setup, no fabricated PIN, no replacement credentials.
    set(&state,"connecting","RP_VERIFY");
    bounded(12,rpc.validate_pairing(&mut record.pair),"RP_VERIFY_FAILED").await?;
    set(&state,"connecting","RP_TUNNEL");
    let port=bounded(12,rpc.create_tcp_listener(),"RP_LISTENER_FAILED").await?;
    let stream=tokio::time::timeout(Duration::from_secs(12),TcpStream::connect(std::net::SocketAddr::from(([10,7,0,1],port)))).await.map_err(|_|"RP_TUNNEL_CONNECT")?.map_err(|_|"RP_TUNNEL_CONNECT")?;
    let tunnel=bounded(20,connect_tls_psk_tunnel_native(stream,rpc.encryption_key()),"RP_TLS_TUNNEL_FAILED").await?;
    let client=tunnel.info.client_address.parse().map_err(|_|"RP_TUNNEL_INFO")?;
    let server=tunnel.info.server_address.parse().map_err(|_|"RP_TUNNEL_INFO")?;
    let mtu=tunnel.info.mtu as usize;let port=tunnel.info.server_rsd_port;
    let mut adapter=idevice::tcp::adapter::Adapter::new(Box::new(tunnel.into_inner()),client,server);
    adapter.set_mss(mtu.saturating_sub(60));let mut adapter=adapter.to_async_handle();
    set(&state,"connecting","RSD_HANDSHAKE");
    let stream=tokio::time::timeout(Duration::from_secs(12),adapter.connect(port)).await.map_err(|_|"RSD_CONNECT_FAILED")?.map_err(|_|"RSD_CONNECT_FAILED")?;
    let mut rsd=bounded(12,RsdHandshake::new(stream),"RSD_HANDSHAKE_FAILED").await?;
    let mut lockdown=bounded(12,LockdownClient::connect_rsd(&mut adapter,&mut rsd),"RSD_LOCKDOWN_FAILED").await?;
    let actual=lockdown.get_value(Some("UniqueDeviceID"),None).await.map_err(|_|"DEVICE_ID_FAILED")?;
    if actual.as_string()!=Some(record.udid.as_str()){return Err("DEVICE_MISMATCH")}
    Ok((adapter,rsd,port,rpc))
}
/// Verify a newly created record against this phone through the local VPN.
/// No DDI mounting, Runner launch or UI operation takes place here.
pub async fn verify_identity(bytes:&[u8],state:&Arc<Mutex<Value>>)->Result<(),&'static str>{
    let mut record=parse(bytes).ok_or("PAIRING_INVALID")?;
    connect(&mut record,state).await?;
    Ok(())
}
pub async fn run(mut record:Record,c:Config,state:Arc<Mutex<Value>>)->Result<(),&'static str>{
    let (mut adapter,mut rsd,port,_pairing_control)=connect(&mut record,&state).await?;
    let mut lockdown=bounded(12,LockdownClient::connect_rsd(&mut adapter,&mut rsd),"RSD_LOCKDOWN_FAILED").await?;
    let version=lockdown.get_value(Some("ProductVersion"),None).await.map_err(|_|"DEVICE_INFO_FAILED")?;
    let major=version.as_string().and_then(|s|s.split('.').next()).and_then(|s|s.parse::<u8>().ok()).ok_or("DEVICE_INFO_FAILED")?;
    set(&state,"checkingImage","DDI_CHECK");
    let mut mounter=ImageMounter::connect_rsd(&mut adapter,&mut rsd).await.map_err(|_|"DDI_SERVICE_FAILED")?;
    if !mounter.query_developer_mode_status().await.map_err(|_|"DEVELOPER_MODE_FAILED")?{return Err("DEVELOPER_MODE_DISABLED")}
    // iOS 27 mounts a Cryptex DDI, which LookupImage("Personalized") does not report.
    // The advertised DDI-only XCTest services are the readiness evidence.
    let ddi_ready=rsd.services.contains_key("com.apple.instruments.dtservicehub")
        && rsd.services.contains_key("com.apple.dt.testmanagerd.remote");
    if !ddi_ready {
        let root=std::path::Path::new(c.ddi_directory.as_deref().ok_or("DDI_REQUIRED")?);
        if major>=27 {
            set(&state,"mountingImage","DDI_CRYPTEX_MOUNT");
            let manifest=std::fs::read(root.join("BuildManifest.plist")).map_err(|_|"DDI_CRYPTEX_REQUIRED")?;
            let manifest:plist::Dictionary=plist::from_bytes(&manifest).map_err(|_|"DDI_INVALID_MANIFEST")?;
            let identity=idevice::tss::select_cryptex_build_identity(&manifest).map_err(|_|"DDI_INVALID_MANIFEST")?.clone();
            let read=|name:&str|std::fs::read(root.join(name)).map_err(|_|"DDI_CRYPTEX_REQUIRED");
            let assets=idevice::cryptexd::Cryptex1Assets::from_parts(read("Image.dmg")?,read("Image.dmg.trustcache")?,read("Image.dmg.cryptex_info")?,read("Image.dmg.root_hash")?,identity);
            let mount:std::pin::Pin<Box<dyn std::future::Future<Output=Result<idevice::cryptexd::InstalledCryptex,IdeviceError>>+Send+'_>>=Box::pin(idevice::cryptexd::install_ddi(&mut adapter,&mut rsd,&assets));
            mount.await.map_err(|_|"DDI_CRYPTEX_MOUNT_FAILED")?;
        } else if mounter.lookup_image("Personalized").await.is_err(){
            let image=std::fs::read(root.join("Image.dmg")).map_err(|_|"DDI_FILES_MISSING")?;
            let trust=std::fs::read(root.join("Image.dmg.trustcache")).map_err(|_|"DDI_FILES_MISSING")?;
            let manifest=std::fs::read(root.join("BuildManifest.plist")).map_err(|_|"DDI_FILES_MISSING")?;
            let chip=lockdown.get_value(Some("UniqueChipID"),None).await.map_err(|_|"DEVICE_INFO_FAILED")?.as_unsigned_integer().ok_or("DEVICE_INFO_FAILED")?;
            set(&state,"mountingImage","DDI_MOUNT");
            mounter=ImageMounter::connect_rsd(&mut adapter,&mut rsd).await.map_err(|_|"DDI_SERVICE_FAILED")?;
            mounter.mount_personalized_rsd(&mut adapter,&mut rsd,image,trust,&manifest,None,chip).await.map_err(|_|"DDI_MOUNT_FAILED")?;
        }
        // DDI adds services; do not reuse the pre-mount service list.
        let stream=adapter.connect(port).await.map_err(|_|"RSD_CONNECT_FAILED")?;
        rsd=RsdHandshake::new(stream).await.map_err(|_|"RSD_HANDSHAKE_FAILED")?;
    }
    let mut proxy=InstallationProxyClient::connect_rsd(&mut adapter,&mut rsd).await.map_err(|_|"RUNNER_LOOKUP_FAILED")?;
    let mut config=TestConfig::from_installation_proxy(&mut proxy,&c.runner_bundle_id,None).await.map_err(|_|"RUNNER_NOT_INSTALLED")?;
    let mut env=plist::Dictionary::new();env.insert("USE_IP".into(),"127.0.0.1".into());env.insert("USE_PORT".into(),c.port.to_string().into());env.insert("LINEDRAW_LOCAL_ONLY".into(),"1".into());config.runner_env=Some(env);
    set(&state,"startingRunner","RUNNER_START");
    XCUITestService::run_rsd(config,major,adapter,&rsd,&mut Listener,None).await.map_err(|_|"XCTEST_SESSION_FAILED")
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn remote_record_requires_device_binding_and_matching_keys(){
        let r=RpPairingFile::generate("unit-test");let bytes=r.to_bytes();assert!(parse(&bytes).is_none());
        let mut p:plist::Dictionary=plist::from_bytes(&bytes).unwrap();p.insert("LineDrawDeviceUDID".into(),"fixture-device".into());
        let mut bytes=Vec::new();plist::to_writer_xml(&mut bytes,&p).unwrap();assert!(parse(&bytes).is_some());
        p.insert("private_key".into(),plist::Value::Data(vec![0;32]));bytes.clear();plist::to_writer_xml(&mut bytes,&p).unwrap();assert!(parse(&bytes).is_none());
    }
}
