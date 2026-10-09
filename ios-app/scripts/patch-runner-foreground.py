"""Resolve a foreground application without constructing its UI snapshot."""
from pathlib import Path
import sys

def patch(root):
    path=Path(root)/'WebDriverAgentLib/Commands/FBCustomCommands.m'
    source=path.read_text()
    marker='// LineDraw: resolve the host application rather than a WebContent hit.'
    eager='id<FBXCAccessibilityElement> hit = FBActiveAppDetectionPoint.sharedInstance.axElement;'
    lazy='id<FBXCAccessibilityElement> hit = infos.count > 1 ? FBActiveAppDetectionPoint.sharedInstance.axElement : nil;'
    if marker in source:
        path.write_text(source.replace(eager,lazy))
        return
    old='  // LineDraw: identify the on-screen process without an application snapshot.'
    if old in source:
        start=source.index(old)
        end=source.index('\n  }',start)+len('\n  }')
        source=source[:start]+source[end:]
    for header in ['FBActiveAppDetectionPoint.h','FBXCAXClientProxy.h','FBXCAccessibilityElement.h']:
        if '#import "'+header+'"' not in source:
            source=source.replace('#import "FBConfiguration.h"','#import "FBConfiguration.h"\n#import "'+header+'"')
    anchor='+ (id<FBResponsePayload>)handleActiveAppInfo:(FBRouteRequest *)request\n{'
    assert source.count(anchor)==1, 'Unexpected WDA activeAppInfo implementation'
    source=source.replace(anchor,anchor+'''
  // LineDraw: resolve the host application rather than a WebContent hit.
  // Web views can return their child process at the detection point. Only
  // identities from the system's active application list may authorize a tap.
  if (NSProcessInfo.processInfo.environment[@"LINEDRAW_LOCAL_ONLY"]) {
    NSArray *elements = [FBXCAXClientProxy.sharedClient activeApplications];
    NSArray<NSDictionary *> *infos = [XCUIApplication fb_appsInfoWithAxElements:elements];
    id<FBXCAccessibilityElement> hit = infos.count > 1 ? FBActiveAppDetectionPoint.sharedInstance.axElement : nil;
    NSDictionary *info = nil;
    for (NSDictionary *candidate in infos) {
      if (hit != nil && [candidate[@"pid"] intValue] == hit.processIdentifier) {
        info = candidate;
        break;
      }
    }
    if (info == nil && infos.count == 1) {
      info = infos.firstObject;
    }
    if (info == nil) {
      // SpringBoard may coexist with one foreground app. Ambiguity remains
      // unknown; never fill in the expected LINE/Safari identity.
      NSArray *apps = [infos filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *candidate, NSDictionary *bindings) {
        NSString *bundle = candidate[@"bundleId"];
        return bundle != nil && ![bundle isEqualToString:@"com.apple.springboard"] && ![bundle isEqualToString:@"unknown"];
      }]];
      if (apps.count == 1) { info = apps.firstObject; }
    }
    return FBResponseWithObject(@{
      @"pid": info[@"pid"] ?: @0,
      @"bundleId": info[@"bundleId"] ?: @"unknown",
      @"name": @"unknown",
      @"processArguments": @{}
    });
  }
''')
    path.write_text(source)

if __name__=='__main__':
    patch(sys.argv[1])
