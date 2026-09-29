import {fingerprint} from '../src/screen.mjs';
export function node(label, options = {}) {
  return {labels:[label],type:'XCUIElementTypeButton',visible:true,enabled:true,source:'native',rect:{x:0,y:720,width:390,height:65},...options};
}
export function page(labels = [], extra = {}) {
  const nodes = [node('官方帳號優惠券',{type:'XCUIElementTypeStaticText',rect:{x:10,y:30,width:250,height:40}}), ...labels.map(l=>typeof l==='string'?node(l):l)];
  return {bundleId:'jp.naver.line',expectedBundle:'jp.naver.line',width:390,height:844,nodes,fingerprint:fingerprint(nodes),...extra};
}
