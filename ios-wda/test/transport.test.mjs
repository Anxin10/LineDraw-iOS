import test from 'node:test';
import assert from 'node:assert/strict';
import {AppiumDriver, localUrl} from '../src/appium.mjs';
import {FIVE_LINKS} from '../src/catalog.mjs';

test('driver only accepts local Appium/WDA endpoints',()=>{
  for(const url of ['https://example.com','http://192.168.1.2:8100','http://127.0.0.1.evil:8100','http://user:pass@127.0.0.1:8100'])assert.throws(()=>localUrl(url));
  assert.equal(localUrl('http://127.0.0.1:4725/'),'http://127.0.0.1:4725');
});
test('connect uses XCUITest, preserves LINE data and never auto-accepts alerts',async()=>{
  const calls=[];const d=new AppiumDriver({fetchImpl:async(url,options)=>{
    calls.push({url,...options,body:options.body?JSON.parse(options.body):undefined});
    return {ok:true,json:async()=>({value:url.endsWith('/session')?{sessionId:'abc',capabilities:{platformVersion:'26.2'}}:url.endsWith('/window/rect')?{width:440,height:956}:null})};
  }});
  await d.connect({udid:'00000000-0000000000000000',mode:'xcode',teamId:'ABCDEFGHIJ'});
  const caps=calls[0].body.capabilities.alwaysMatch;
  assert.equal(caps['appium:bundleId'],'jp.naver.line');assert.equal(caps['appium:noReset'],true);assert.equal(caps['appium:autoAcceptAlerts'],false);
  assert.equal(caps['appium:autoLaunch'],false);assert.equal(caps['appium:shouldTerminateApp'],false);
  assert.equal(caps['appium:usePreinstalledWDA'],undefined);assert.equal(d.sessionId,'abc');
  assert.deepEqual(calls.find(c=>c.url.endsWith('/appium/settings')).body,{settings:{activeAppDetectionPoint:'220,478'}});
});
test('attach uses WDA URL and does not accidentally select preinstalled launch mode',async()=>{
  let caps;const d=new AppiumDriver({fetchImpl:async(url,options)=>{if(url.endsWith('/session'))caps=JSON.parse(options.body).capabilities.alwaysMatch;return {ok:true,json:async()=>({value:url.endsWith('/window/rect')?{width:440,height:956}:{sessionId:'abc'}})};}});
  await d.connect({udid:'abcdefgh',mode:'attach',wdaUrl:'http://127.0.0.1:8105'});
  assert.equal(caps['appium:webDriverAgentUrl'],'http://127.0.0.1:8105');assert.equal(caps['appium:usePreinstalledWDA'],undefined);
});
test('foreground sampling follows screen rotation without forcing LINE to be active',async()=>{
  const d=new AppiumDriver();d.sessionId='test';const calls=[];d.request=async(...args)=>calls.push(args);
  await d.configureForegroundDetection({width:440,height:956});await d.configureForegroundDetection({width:440,height:956});
  await d.configureForegroundDetection({width:956,height:440});
  assert.equal(calls.length,2);assert.deepEqual(calls[1][2],{settings:{activeAppDetectionPoint:'478,220'}});
  await assert.rejects(()=>d.configureForegroundDetection({width:0,height:956}),/尺寸/);
});
test('invalid session response is not a successful connection',async()=>{
  const d=new AppiumDriver({fetchImpl:async()=>({ok:true,json:async()=>({value:{}})})});
  await assert.rejects(()=>d.connect({udid:'abcdefgh'}),/session ID/);assert.equal(d.sessionId,null);
});
test('open dispatches LIFF as a Universal Link and checks cancellation before dispatch',async()=>{
  const d=new AppiumDriver();const calls=[];d.snapshot=async()=>({nodes:[],height:844,bundleId:'jp.naver.line',fingerprint:'old'});d.execute=async(...args)=>calls.push(args);
  assert.equal(await d.open(FIVE_LINKS[0].url),'old');assert.deepEqual(calls[0],['mobile: deepLink',{url:FIVE_LINKS[0].url}]);
  await assert.rejects(()=>d.open(FIVE_LINKS[1].url,()=>false),e=>e.notDispatched);assert.equal(calls.length,1);
});
test('driver failures redact response page text from normal logs',async()=>{
  const d=new AppiumDriver({fetchImpl:async()=>({ok:false,status:500,json:async()=>({value:{error:'unknown error',message:'private account and chat'}})})});
  await assert.rejects(()=>d.request('GET','/status'),e=>!e.message.includes('private account')&&e.message.includes('unknown error'));
});
