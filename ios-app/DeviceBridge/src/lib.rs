//! LineDraw-owned, narrow FFI. The pinned idevice dependency retains its MIT license.
//! Pairing advertises only during explicit setup. No credentials or upstream debug messages are logged.
mod remote;
mod phone_pairing;
use std::{ffi::{c_char, CStr, CString}, sync::{Arc, Mutex, OnceLock}, time::Duration};
use idevice::{IdeviceService,IdeviceError, pairing_file::PairingFile, provider::{IdeviceProvider,TcpProvider}, services::{lockdown::LockdownClient, heartbeat::HeartbeatClient, mobile_image_mounter::ImageMounter, installation_proxy::InstallationProxyClient, dvt::xctest::{TestConfig,XCUITestService,listener::XCUITestListener}}};
use serde::Deserialize;
use serde_json::{json,Value};
use tokio::{runtime::Runtime,task::JoinHandle};
#[derive(Deserialize)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
struct Config { runner_bundle_id:String, port:u16, ddi_directory:Option<String> }
struct Session { task: Option<JoinHandle<()>>, state:Arc<Mutex<Value>> }
static RUNTIME:OnceLock<Runtime>=OnceLock::new();
static SESSION:Mutex<Option<Session>>=Mutex::new(None);
fn runtime()->&'static Runtime { RUNTIME.get_or_init(|| tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all().build().expect("runtime")) }
fn set(state:&Arc<Mutex<Value>>,stage:&str,code:&str){ *state.lock().unwrap()=json!({"stage":stage,"code":code}); }
fn output(v:Value)->*mut c_char {CString::new(v.to_string()).unwrap().into_raw()}
fn valid_config(c:&Config)->bool {c.runner_bundle_id.ends_with(".xctrunner") && c.runner_bundle_id.len()<180 && c.runner_bundle_id.bytes().all(|b|b.is_ascii_alphanumeric() || b==b'.' || b==b'-') && c.port>=49152}
fn pairing_error(error:IdeviceError)->&'static str {
    match error {
        IdeviceError::InvalidHostID=>"PAIRING_HOST_REJECTED",
        IdeviceError::DeviceLocked=>"DEVICE_LOCKED",
        IdeviceError::Socket(e)=>{
            let text=e.to_string();
            if text.contains("BadCertificate"){return "PAIRING_TLS_BAD_CERTIFICATE"}
            if text.contains("HandshakeFailure"){return "PAIRING_TLS_HANDSHAKE_FAILURE"}
            if text.contains("CertificateRequired"){return "PAIRING_TLS_CERTIFICATE_REQUIRED"}
            if text.contains("UnknownCA"){return "PAIRING_TLS_UNKNOWN_CA"}
            if text.contains("DecryptError"){return "PAIRING_TLS_DECRYPT_ERROR"}
            match e.kind(){std::io::ErrorKind::InvalidData=>"PAIRING_TLS_INVALID_DATA",std::io::ErrorKind::UnexpectedEof=>"PAIRING_TLS_EOF",std::io::ErrorKind::ConnectionReset=>"PAIRING_CONNECTION_RESET",std::io::ErrorKind::BrokenPipe=>"PAIRING_BROKEN_PIPE",std::io::ErrorKind::InvalidInput=>"PAIRING_INVALID_INPUT",std::io::ErrorKind::PermissionDenied=>"PAIRING_PERMISSION_DENIED",_=>"PAIRING_SOCKET_OTHER"}
        },
        IdeviceError::Rustls(_)=>"PAIRING_TLS_CONFIGURATION",
        IdeviceError::UnexpectedResponse(ref s) if s.contains("missing EnableSessionSSL")=>"PAIRING_SESSION_REJECTED",
        _=>"PAIRING_REJECTED"
    }
}
struct Listener;
impl XCUITestListener for Listener {}
async fn run(pairing:PairingFile,c:Config,state:Arc<Mutex<Value>>)->Result<(),&'static str>{
    let provider:Arc<dyn IdeviceProvider>=Arc::new(TcpProvider{addr:"10.7.0.1".parse().unwrap(),scope_id:None,pairing_file:pairing,label:"LineDraw-device".into()});
    set(&state,"connecting","VPN_CONNECT");
    let mut lockdown=tokio::time::timeout(Duration::from_secs(12),LockdownClient::connect(&*provider)).await.map_err(|_|"VPN_TIMEOUT")?.map_err(|_|"VPN_CONNECT_FAILED")?;
    set(&state,"connecting","VPN_SERVICE_PROBE");
    tokio::time::timeout(Duration::from_secs(10),lockdown.idevice.get_type()).await.map_err(|_|"VPN_SERVICE_TIMEOUT")?.map_err(|_|"VPN_QUERY_TYPE_CLOSED")?;
    tokio::time::timeout(Duration::from_secs(10),lockdown.get_value(Some("ProductVersion"),None)).await.map_err(|_|"VPN_SERVICE_TIMEOUT")?.map_err(|_|"VPN_SERVICE_CLOSED")?;
    let pair=provider.get_pairing_file().await.map_err(|_|"PAIRING_INVALID")?;
    tokio::time::timeout(Duration::from_secs(12),lockdown.start_session(&pair)).await.map_err(|_|"PAIRING_TIMEOUT")?.map_err(pairing_error)?;
    if let Some(expected)=pair.udid {
        let actual=lockdown.get_value(Some("UniqueDeviceID"),None).await.map_err(|_|"DEVICE_ID_FAILED")?;
        if actual.as_string()!=Some(expected.as_str()){return Err("DEVICE_MISMATCH")}
    }
    let mut heartbeat=HeartbeatClient::connect(&*provider).await.map_err(|_|"HEARTBEAT_FAILED")?;
    let work=async {
        set(&state,"checkingImage","DDI_CHECK");
        let mut mounter=ImageMounter::connect(&*provider).await.map_err(|_|"DDI_SERVICE_FAILED")?;
        if !mounter.query_developer_mode_status().await.map_err(|_|"DEVELOPER_MODE_FAILED")? {return Err("DEVELOPER_MODE_DISABLED")}
        if mounter.lookup_image("Personalized").await.is_err(){
            let dir=c.ddi_directory.as_deref().ok_or("DDI_REQUIRED")?;
            set(&state,"mountingImage","DDI_MOUNT");
            let root=std::path::Path::new(dir);
            // The app copies individually selected files to its own protected directory.
            let image=std::fs::read(root.join("Image.dmg")).map_err(|_|"DDI_FILES_MISSING")?;
            let trust=std::fs::read(root.join("Image.dmg.trustcache")).map_err(|_|"DDI_FILES_MISSING")?;
            let manifest=std::fs::read(root.join("BuildManifest.plist")).map_err(|_|"DDI_FILES_MISSING")?;
            let chip=lockdown.get_value(Some("UniqueChipID"),None).await.map_err(|_|"DEVICE_INFO_FAILED")?.as_unsigned_integer().ok_or("DEVICE_INFO_FAILED")?;
            mounter=ImageMounter::connect(&*provider).await.map_err(|_|"DDI_SERVICE_FAILED")?;
            mounter.mount_personalized(&*provider,image,trust,&manifest,None,chip).await.map_err(|_|"DDI_MOUNT_FAILED")?;
        }
        set(&state,"startingRunner","RUNNER_START");
        let mut proxy=InstallationProxyClient::connect(&*provider).await.map_err(|_|"RUNNER_LOOKUP_FAILED")?;
        let mut config=TestConfig::from_installation_proxy(&mut proxy,&c.runner_bundle_id,None).await.map_err(|_|"RUNNER_NOT_INSTALLED")?;
        let mut env=plist::Dictionary::new();
        env.insert("USE_IP".into(),"127.0.0.1".into());
        env.insert("USE_PORT".into(),c.port.to_string().into());
        env.insert("LINEDRAW_LOCAL_ONLY".into(),"1".into());
        config.runner_env=Some(env);
        let service=XCUITestService::new(provider.clone());
        // Swift independently probes localhost HTTP; this state is never called "ready".
        service.run(config,&mut Listener,None).await.map_err(|_|"XCTEST_SESSION_FAILED")?;
        Ok(())
    };
    let beat=async {
        let mut interval=30;
        loop {interval=heartbeat.get_marco(interval+5).await.map_err(|_|"HEARTBEAT_LOST")?;heartbeat.send_polo().await.map_err(|_|"HEARTBEAT_LOST")?;}
        #[allow(unreachable_code)] Ok::<(),&'static str>(())
    };
    tokio::select! {r=work=>r,r=beat=>r}
}
/// Safety: callers provide valid buffers and a NUL-terminated configuration.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ld_validate_pairing(bytes:*const u8,len:usize)->std::ffi::c_int {
    if bytes.is_null() || len==0 || len>1_000_000{return 0}
    let data=unsafe{std::slice::from_raw_parts(bytes,len)};
    i32::from(remote::parse(data).is_some() || PairingFile::from_bytes(data).is_ok())
}
/// Safety: callers provide valid buffers and a NUL-terminated configuration.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ld_start(bytes:*const u8,len:usize,configuration:*const c_char)->*mut c_char {
    if bytes.is_null() || configuration.is_null() || len==0 || len>1_000_000{return output(json!({"error":"INVALID_INPUT"}))}
    let mut global=SESSION.lock().unwrap();
    if global.is_some() || phone_pairing::active(){return output(json!({"error":"SESSION_EXISTS"}))}
    let Ok(c)=serde_json::from_slice::<Config>(unsafe{CStr::from_ptr(configuration)}.to_bytes()) else{return output(json!({"error":"INVALID_CONFIG"}))};
    if !valid_config(&c){return output(json!({"error":"INVALID_CONFIG"}))}
    let data=unsafe{std::slice::from_raw_parts(bytes,len)};
    let remote=remote::parse(data);
    let classic=if remote.is_none(){PairingFile::from_bytes(data).ok()}else{None};
    if remote.is_none() && classic.is_none(){return output(json!({"error":"PAIRING_INVALID"}))}
    let state=Arc::new(Mutex::new(json!({"stage":"starting","code":"STARTING"})));let copy=state.clone();
    let task=runtime().spawn(async move {
        let result=if let Some(pair)=remote{remote::run(pair,c,copy.clone()).await}else{run(classic.unwrap(),c,copy.clone()).await};
        match result {Ok(())=>set(&copy,"stopped","RUNNER_EXITED"),Err(code)=>set(&copy,"failed",code)}
    });
    *global=Some(Session{task:Some(task),state});output(json!({"started":true}))
}
#[unsafe(no_mangle)]
pub extern "C" fn ld_status()->*mut c_char {let global=SESSION.lock().unwrap();output(global.as_ref().map(|s|s.state.lock().unwrap().clone()).unwrap_or(json!({"stage":"stopped","code":"STOPPED"})))}
#[unsafe(no_mangle)]
pub extern "C" fn ld_stop(){if let Some(mut s)=SESSION.lock().unwrap().take(){if let Some(t)=s.task.take(){t.abort();}}}
/// Safety: only accepts pointers returned by this library, once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ld_string_free(value:*mut c_char){if !value.is_null(){drop(unsafe{CString::from_raw(value)})}}
#[cfg(test)] static TEST_GLOBAL_LOCK:Mutex<()>=Mutex::new(());
#[cfg(test)] mod tests {use super::*;
 #[test] fn validates_runner_and_port(){assert!(valid_config(&Config{runner_bundle_id:"com.example.Runner.xctrunner".into(),port:53000,ddi_directory:None}));assert!(!valid_config(&Config{runner_bundle_id:"com.example.App".into(),port:8100,ddi_directory:None}));}
 #[test] fn invalid_pairing_never_starts(){let _guard=TEST_GLOBAL_LOCK.lock().unwrap();let config=CString::new(r#"{"runnerBundleId":"com.example.Runner.xctrunner","port":53000}"#).unwrap();let p=unsafe{ld_start(b"bad".as_ptr(),3,config.as_ptr())};let text=unsafe{CStr::from_ptr(p)}.to_str().unwrap().to_owned();unsafe{ld_string_free(p)};assert!(text.contains("PAIRING_INVALID"));}
}
