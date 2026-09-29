//! Explicit iOS 27 device-initiated pairing using the MIT idevice responder.
//! Swift publishes Bonjour and shows the temporary PIN. No imported host record.
use super::*;
use idevice::remote_pairing::{PairableHost, PairableHostInfo, RpPairingFile, RpPairingSocket};
use std::net::{IpAddr, Ipv4Addr};
use zeroize::Zeroizing;

#[derive(Deserialize)]
#[serde(rename_all="camelCase", deny_unknown_fields)]
struct PairConfig { local_addresses:Vec<Ipv4Addr> }
struct PairSession {
    task:JoinHandle<()>,
    state:Arc<Mutex<Value>>,
    record:Arc<Mutex<Option<Zeroizing<Vec<u8>>>>>,
}
static PAIRING:Mutex<Option<PairSession>>=Mutex::new(None);
pub fn active()->bool { PAIRING.lock().unwrap().is_some() }
fn valid(c:&PairConfig)->bool {
    !c.local_addresses.is_empty() && c.local_addresses.len()<=32 &&
        c.local_addresses.iter().all(|a|!a.is_unspecified() && !a.is_multicast() && !a.is_broadcast())
}
fn allowed(peer:IpAddr,c:&PairConfig)->bool {
    matches!(peer,IpAddr::V4(a) if c.local_addresses.contains(&a))
}
fn encode(pair:&RpPairingFile,udid:&str,host_irk:[u8;16])->Result<Zeroizing<Vec<u8>>,&'static str>{
    if udid.is_empty() || udid.len()>64 || !udid.bytes().all(|c|c.is_ascii_alphanumeric() || c==b'-'){return Err("DEVICE_ID_FAILED")}
    let original=Zeroizing::new(pair.to_bytes());
    let mut p:plist::Dictionary=plist::from_bytes(&original).map_err(|_|"PAIRING_INVALID")?;
    p.insert("LineDrawDeviceUDID".into(),udid.into());
    p.insert("LineDrawHostAltIRK".into(),plist::Value::Data(host_irk.to_vec()));
    p.insert("LineDrawPairingOrigin".into(),"phone-ios27".into());
    let mut bytes=Zeroizing::new(Vec::new());
    plist::to_writer_xml(&mut *bytes,&p).map_err(|_|"PAIRING_INVALID")?;
    if remote::parse(&bytes).is_none(){return Err("PAIRING_INVALID")}
    Ok(bytes)
}
async fn pair(c:PairConfig,state:Arc<Mutex<Value>>,result:Arc<Mutex<Option<Zeroizing<Vec<u8>>>>>)->Result<(),&'static str>{
    let listener=tokio::net::TcpListener::bind((Ipv4Addr::UNSPECIFIED,0)).await.map_err(|_|"PAIR_LISTEN_FAILED")?;
    let port=listener.local_addr().map_err(|_|"PAIR_LISTEN_FAILED")?.port();
    let host=PairableHostInfo::generate("LineDraw","Mac17,7");
    // Fresh host identity for each explicit pairing; never impersonate an imported host.
    let name=format!("LineDraw-{}-{:?}",std::process::id(),std::time::SystemTime::now());
    let mut record=RpPairingFile::generate(&name);
    let txt:std::collections::BTreeMap<_,_>=host.mdns_txt_records(&record.identifier).into_iter().collect();
    *state.lock().unwrap()=json!({"stage":"advertising","port":port,"name":record.identifier,"txt":txt});
    let stream=loop {
        let (stream,peer)=listener.accept().await.map_err(|_|"PAIR_ACCEPT_FAILED")?;
        // Only this phone's own interface addresses may enter the PIN handshake.
        if allowed(peer.ip(),&c){break stream}
    };
    // Keep the listening endpoint alive while Settings owns the pairing dialog.
    set(&state,"handshake","PAIR_HANDSHAKE");
    let host_irk=host.alt_irk;
    let mut responder=PairableHost::new(RpPairingSocket::new_device(stream),host);
    let pin_state=state.clone();
    let peer=responder.accept(&mut record,move |pin| async move {
        *pin_state.lock().unwrap()=json!({"stage":"pin","pin":pin});
    }).await.map_err(|_|"PAIR_SETUP_FAILED")?;
    set(&state,"verifying","PAIR_VERIFY_LOCAL");
    let bytes=encode(&record,&peer.remotepairing_udid,host_irk)?;
    // Allow iOS to commit M6 before opening a separate pair-verify session.
    tokio::time::sleep(Duration::from_millis(500)).await;
    remote::verify_identity(&bytes,&state).await?;
    drop(responder);drop(listener);
    *result.lock().unwrap()=Some(bytes);
    set(&state,"complete","PAIR_COMPLETE");
    Ok(())
}

/// Safety: configuration must be NUL-terminated UTF-8 JSON.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ld_pair_start(configuration:*const c_char)->*mut c_char{
    if configuration.is_null(){return output(json!({"error":"INVALID_CONFIG"}))}
    let Ok(c)=serde_json::from_slice::<PairConfig>(unsafe{CStr::from_ptr(configuration)}.to_bytes()) else{return output(json!({"error":"INVALID_CONFIG"}))};
    if !valid(&c){return output(json!({"error":"INVALID_CONFIG"}))}
    // Common lock order with ld_start: SESSION, then PAIRING.
    let running=SESSION.lock().unwrap();
    let mut global=PAIRING.lock().unwrap();
    if running.is_some() || global.is_some(){return output(json!({"error":"SESSION_EXISTS"}))}
    let state=Arc::new(Mutex::new(json!({"stage":"starting"})));
    let record=Arc::new(Mutex::new(None));let status=state.clone();let result=record.clone();
    let task=runtime().spawn(async move {
        let outcome=tokio::time::timeout(Duration::from_secs(240),pair(c,status.clone(),result.clone())).await;
        let error=match outcome{Ok(Ok(()))=>None,Ok(Err(code))=>Some(code),Err(_)=>Some("PAIR_TIMEOUT")};
        if let Some(code)=error{result.lock().unwrap().take();set(&status,"failed",code)}
    });
    *global=Some(PairSession{task,state,record});
    output(json!({"started":true}))
}
#[unsafe(no_mangle)]
pub extern "C" fn ld_pair_status()->*mut c_char{
    let global=PAIRING.lock().unwrap();
    output(global.as_ref().map(|s|s.state.lock().unwrap().clone()).unwrap_or(json!({"stage":"stopped"})))
}
#[unsafe(no_mangle)]
pub extern "C" fn ld_pair_stop(){
    if let Some(s)=PAIRING.lock().unwrap().take(){s.task.abort();s.record.lock().unwrap().take();set(&s.state,"stopped","STOPPED")}
}
fn take_record(record:&mut Option<Zeroizing<Vec<u8>>>,buffer:*mut u8,capacity:usize)->usize{
    let Some(bytes)=record.as_ref() else{return 0};let size=bytes.len();
    if !buffer.is_null() && capacity>=size {
        // Safety follows the FFI caller's writable-buffer contract.
        unsafe{std::ptr::copy_nonoverlapping(bytes.as_ptr(),buffer,size)};
        record.take();
    }
    size
}
/// Safety: a non-null buffer must be writable for capacity bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ld_pair_take_record(buffer:*mut u8,capacity:usize)->usize{
    let global=PAIRING.lock().unwrap();let Some(s)=global.as_ref() else{return 0};
    take_record(&mut s.record.lock().unwrap(),buffer,capacity)
}

#[cfg(test)] mod tests {
    use super::*;
    fn read(pointer:*mut c_char)->Value{
        let value=serde_json::from_slice(unsafe{CStr::from_ptr(pointer)}.to_bytes()).unwrap();
        unsafe{ld_string_free(pointer)};value
    }
    fn wait_stage(stage:&str)->Value{
        let until=std::time::Instant::now()+Duration::from_secs(3);
        loop{let value=read(ld_pair_status());if value["stage"]==stage{return value}
            assert!(std::time::Instant::now()<until,"expected {stage}");std::thread::sleep(Duration::from_millis(10));}
    }
    #[test] fn cancel_closes_listener_and_excludes_runner_and_secret_export(){
        let _guard=TEST_GLOBAL_LOCK.lock().unwrap();ld_pair_stop();ld_stop();
        let config=CString::new(r#"{"localAddresses":["127.0.0.1"]}"#).unwrap();
        assert_eq!(read(unsafe{ld_pair_start(config.as_ptr())})["started"],true);
        let state=wait_stage("advertising");
        assert!(state.get("pin").is_none());assert!(state.get("private_key").is_none());
        assert_eq!(unsafe{ld_pair_take_record(std::ptr::null_mut(),0)},0);
        let runner=CString::new(r#"{"runnerBundleId":"com.test.xctrunner","port":53000}"#).unwrap();
        assert_eq!(read(unsafe{ld_start(b"bad".as_ptr(),3,runner.as_ptr())})["error"],"SESSION_EXISTS");
        assert_eq!(read(unsafe{ld_pair_start(config.as_ptr())})["error"],"SESSION_EXISTS");
        let port=state["port"].as_u64().unwrap() as u16;
        ld_pair_stop();assert!(!active());assert_eq!(read(ld_pair_status())["stage"],"stopped");
        let until=std::time::Instant::now()+Duration::from_secs(2);
        while std::net::TcpStream::connect((Ipv4Addr::LOCALHOST,port)).is_ok(){assert!(std::time::Instant::now()<until);std::thread::sleep(Duration::from_millis(10));}
    }
    #[test] fn incomplete_handshake_never_yields_credentials(){
        let _guard=TEST_GLOBAL_LOCK.lock().unwrap();ld_pair_stop();ld_stop();
        let config=CString::new(r#"{"localAddresses":["127.0.0.1"]}"#).unwrap();
        read(unsafe{ld_pair_start(config.as_ptr())});let state=wait_stage("advertising");
        let port=state["port"].as_u64().unwrap() as u16;
        drop(std::net::TcpStream::connect((Ipv4Addr::LOCALHOST,port)).unwrap());
        let failure=wait_stage("failed");assert_eq!(failure["code"],"PAIR_SETUP_FAILED");
        assert_eq!(unsafe{ld_pair_take_record(std::ptr::null_mut(),0)},0);assert!(failure.get("pin").is_none());ld_pair_stop();
    }
    #[test] fn listening_endpoint_survives_while_settings_is_handshaking(){
        let _guard=TEST_GLOBAL_LOCK.lock().unwrap();ld_pair_stop();ld_stop();
        let config=CString::new(r#"{"localAddresses":["127.0.0.1"]}"#).unwrap();
        read(unsafe{ld_pair_start(config.as_ptr())});let state=wait_stage("advertising");
        let port=state["port"].as_u64().unwrap() as u16;
        let first=std::net::TcpStream::connect((Ipv4Addr::LOCALHOST,port)).unwrap();
        wait_stage("handshake");
        // The system must not see a disappearing service while it collects passcode/PIN.
        let probe=std::net::TcpStream::connect((Ipv4Addr::LOCALHOST,port)).unwrap();
        assert_eq!(unsafe{ld_pair_take_record(std::ptr::null_mut(),0)},0);
        ld_pair_stop();drop(first);drop(probe);
    }
    #[test] fn rejects_nonlocal_peers_and_bad_config(){
        let c=PairConfig{local_addresses:vec![Ipv4Addr::LOCALHOST,"192.168.1.7".parse().unwrap()]};
        assert!(valid(&c));assert!(allowed("192.168.1.7".parse().unwrap(),&c));
        assert!(!allowed("192.168.1.8".parse().unwrap(),&c));assert!(!allowed("::1".parse().unwrap(),&c));
        assert!(!valid(&PairConfig{local_addresses:vec![]}));assert!(!valid(&PairConfig{local_addresses:vec![Ipv4Addr::UNSPECIFIED]}));
    }
    #[test] fn credentials_are_device_bound_and_pinless_disabled(){
        let host=PairableHostInfo::generate("LineDraw","Mac17,7");assert!(!host.allows_pinless_pairing);
        let pair=RpPairingFile::generate("fixture");
        assert!(encode(&pair,"",host.alt_irk).is_err());
        let bytes=encode(&pair,"fixture-device",host.alt_irk).unwrap();
        let parsed=remote::parse(&bytes).unwrap();assert_eq!(parsed.udid,"fixture-device");
        let p:plist::Dictionary=plist::from_bytes(&bytes).unwrap();assert_eq!(p["LineDrawHostAltIRK"].as_data(),Some(host.alt_irk.as_slice()));
    }
    #[test] fn secret_can_only_be_consumed_once_and_small_buffer_preserves_it(){
        let mut record=Some(Zeroizing::new(vec![1,2,3]));let mut small=[0;2];
        assert_eq!(take_record(&mut record,std::ptr::null_mut(),0),3);
        assert_eq!(take_record(&mut record,small.as_mut_ptr(),2),3);assert_eq!(small,[0,0]);
        let mut full=[0;3];assert_eq!(take_record(&mut record,full.as_mut_ptr(),3),3);assert_eq!(full,[1,2,3]);
        assert_eq!(take_record(&mut record,full.as_mut_ptr(),3),0);
    }
}
