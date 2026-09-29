#!/usr/bin/env python3
"""Prepare a separate WDA 16.12.10 source tree. Does not install/start anything."""
import pathlib, shutil, json, subprocess
root=pathlib.Path(__file__).resolve().parents[1]
source=root.parent/'ios-wda/.runtime/appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent'
if json.loads((source/'package.json').read_text())['version']!='16.12.10':
    raise SystemExit('Expected appium-webdriveragent 16.12.10. Run ios-wda setup first.')
out=root/'.runtime/DeviceRunnerSource'
if out.exists():
    raise SystemExit('DeviceRunnerSource exists; retain it or explicitly move it before preparing a new copy.')
shutil.copytree(source,out,ignore=shutil.ignore_patterns('node_modules','.git','build','DerivedData','*.xcuserstate','xcuserdata'))
server=out/'WebDriverAgentLib/Routing/FBWebServer.m'
s=server.read_text();needle='- (void)initScreenshotsBroadcaster\n{'
assert s.count(needle)==1
s=s.replace(needle,needle+'\n  // LineDraw local mode does not expose an MJPEG listener.\n  if (NSProcessInfo.processInfo.environment[@"LINEDRAW_LOCAL_ONLY"]) { return; }')
server.write_text(s)
# The source package includes the previous developer's local team assignment. Strip it.
project=out/'WebDriverAgent.xcodeproj/project.pbxproj'
import re
s=project.read_text();s=re.sub(r'DEVELOPMENT_TEAM = [^;]*;', 'DEVELOPMENT_TEAM = "";',s);project.write_text(s)
ruby='''require 'xcodeproj';p=Xcodeproj::Project.open(ARGV[0]);t=p.targets.find{|x|x.name=='WebDriverAgentRunner'};t.build_configurations.each{|c|c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']='com.beybladehunter.linedraw.DeviceRunner';c.build_settings['CODE_SIGN_STYLE']='Automatic'};p.save'''
subprocess.run(['ruby','-e',ruby,str(out/'WebDriverAgent.xcodeproj')],check=True)
print(out)
