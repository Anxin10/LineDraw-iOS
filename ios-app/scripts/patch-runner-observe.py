"""Add a local-only read-only compact snapshot endpoint to our copied WDA tree."""
from pathlib import Path
import sys

def patch(root):
    path=Path(root)/'WebDriverAgentLib/Commands/FBDebugCommands.m'
    source=path.read_text()
    if '// LineDraw compact observation v3' in source:
        return
    if '// LineDraw compact observation v1' in source or '// LineDraw compact observation v2' in source:
        source=source[:source.index('\n// LineDraw compact observation v')]+source[source.rfind('\n@end'):]
    headers=['FBXCAXClientProxy.h','FBXCAccessibilityElement.h','FBActiveAppDetectionPoint.h','FBXCElementSnapshotWrapper.h','FBElementTypeTransformer.h','FBCommandStatus.h','FBConfiguration.h']
    for header in headers:
        if '#import \"'+header+'\"' in source:
            continue
        source=source.replace('@implementation FBDebugCommands','#import "'+header+'"\n\n@implementation FBDebugCommands',1)
    anchor='    [[FBRoute GET:@"/source"] respondWithTarget:self action:@selector(handleGetSourceCommand:)],'
    assert source.count(anchor)==1
    if '@selector(handleLineDrawObserve:)' not in source:
        source=source.replace(anchor,anchor+'\n    [[FBRoute GET:@"/linedraw/observe"] respondWithTarget:self action:@selector(handleLineDrawObserve:)],')
    method=r'''
// LineDraw compact observation v3: one native snapshot, no XML or screenshot.
+ (NSDictionary *)lineDrawActiveIdentity
{
  NSArray *elements = [FBXCAXClientProxy.sharedClient activeApplications];
  NSArray<NSDictionary *> *infos = [XCUIApplication fb_appsInfoWithAxElements:elements];
  if (infos.count == 1) { return infos.firstObject; }
  id<FBXCAccessibilityElement> hit = FBActiveAppDetectionPoint.sharedInstance.axElement;
  for (NSDictionary *info in infos) {
    if (hit != nil && [info[@"pid"] intValue] == hit.processIdentifier) { return info; }
  }
  NSArray *apps = [infos filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *info, NSDictionary *bindings) {
    NSString *bundle = info[@"bundleId"];
    return bundle != nil && ![bundle isEqualToString:@"unknown"] && ![bundle isEqualToString:@"com.apple.springboard"];
  }]];
  return apps.count == 1 ? apps.firstObject : @{};
}

+ (NSString *)lineDrawNormalized:(NSString *)text
{
  NSString *value = text.precomposedStringWithCompatibilityMapping ?: @"";
  value = [[value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"!！。.…"]];
}

+ (BOOL)lineDrawTextNeeded:(NSString *)text filter:(NSDictionary *)filter
{
  if (filter == nil) { return YES; }
  NSString *value = [self lineDrawNormalized:text];
  if ([filter[@"labels"] containsObject:value]) { return YES; }
  for (NSString *token in filter[@"blockers"]) {
    if ([value.lowercaseString containsString:token]) { return YES; }
  }
  return NO;
}

+ (BOOL)lineDrawCollect:(id<FBXCElementSnapshot>)snapshot nodes:(NSMutableArray *)nodes depth:(NSUInteger)depth count:(NSUInteger *)count viewport:(CGRect)viewport checks:(NSUInteger *)checks skipped:(NSUInteger *)skipped filter:(NSDictionary *)filter
{
  (*count)++;
  if (*count > 20000 || depth >= 64 || nodes.count >= 4096) { return NO; }
  CGRect rect = snapshot.frame;
  NSString *label = snapshot.label;
  NSString *value = [snapshot.value isKindOfClass:NSString.class] ? snapshot.value : nil;
  BOOL hasText = label.length > 0 || value.length > 0;
  BOOL structural = snapshot.elementType == XCUIElementTypeAlert || snapshot.elementType == XCUIElementTypeWebView;
  BOOL outside = !structural && !CGRectIntersectsRect(rect, viewport);
  if (outside && hasText) { (*skipped)++; }
  BOOL needed = structural || (hasText && ([self lineDrawTextNeeded:label filter:filter] || [self lineDrawTextNeeded:value filter:filter]));
  if (!outside && needed && !CGRectIsEmpty(rect) &&
      isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width) && isfinite(rect.size.height)) {
    if ([label lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 65536 || [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 65536) { return NO; }
    id<FBElement> wrapped = (id<FBElement>)[FBXCElementSnapshotWrapper ensureWrapped:snapshot];
    // Compute visibility only for retained labels/buttons, not every container.
    (*checks)++;
    if (wrapped.isWDVisible) {
      [nodes addObject:@{
        @"type": [FBElementTypeTransformer shortStringWithElementType:snapshot.elementType],
        @"label": label ?: @"", @"value": value ?: @"",
        @"rect": @{@"x": @(rect.origin.x), @"y": @(rect.origin.y), @"width": @(rect.size.width), @"height": @(rect.size.height)},
        @"isVisible": @YES, @"isEnabled": @(snapshot.enabled)
      }];
    }
  }
  for (id<FBXCElementSnapshot> child in snapshot.children) {
    if (![self lineDrawCollect:child nodes:nodes depth:depth+1 count:count viewport:viewport checks:checks skipped:skipped filter:filter]) { return NO; }
  }
  return YES;
}

+ (id<FBResponsePayload>)handleLineDrawObserve:(FBRouteRequest *)request
{
  if (!NSProcessInfo.processInfo.environment[@"LINEDRAW_LOCAL_ONLY"]) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Local mode required" traceback:nil]);
  }
  NSString *expected = request.parameters[@"expected_bundle"];
  if (![@[@"jp.naver.line", @"com.apple.mobilesafari"] containsObject:expected]) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Unsupported observation target" traceback:nil]);
  }
  NSDictionary *filter = nil;
  NSString *rawFilter = request.parameters[@"decision_filter"];
  if (rawFilter != nil) {
    NSData *bytes = [rawFilter dataUsingEncoding:NSUTF8StringEncoding];
    id parsed = bytes.length <= 8192 ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
    if (![parsed isKindOfClass:NSDictionary.class] || ![parsed[@"labels"] isKindOfClass:NSArray.class] || ![parsed[@"blockers"] isKindOfClass:NSArray.class] || [parsed[@"labels"] count] > 128 || [parsed[@"blockers"] count] > 32 || [parsed[@"labels"] count] == 0 || [parsed[@"blockers"] count] == 0) {
      return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Invalid decision filter" traceback:nil]);
    }
    for (id token in [parsed[@"labels"] arrayByAddingObjectsFromArray:parsed[@"blockers"]]) {
      if (![token isKindOfClass:NSString.class] || [token length] == 0 || [token lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 1024) {
        return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Invalid decision token" traceback:nil]);
      }
    }
    filter = parsed;
  }
  NSString *bundle = [self lineDrawActiveIdentity][@"bundleId"] ?: @"unknown";
  if (![bundle isEqualToString:expected]) { return FBResponseWithObject(@{@"schema": @1, @"bundleId": bundle, @"ready": @NO}); }
  NSTimeInterval began = NSProcessInfo.processInfo.systemUptime;
  XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:bundle];
  id<FBXCElementSnapshot> snapshot = [app fb_standardSnapshot];
  NSTimeInterval captured = NSProcessInfo.processInfo.systemUptime;
  CGRect viewport = snapshot.frame;
  if (CGRectIsEmpty(viewport) || !isfinite(viewport.origin.x) || !isfinite(viewport.origin.y) || !isfinite(viewport.size.width) || !isfinite(viewport.size.height)) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Invalid snapshot viewport" traceback:nil]);
  }
  NSUInteger checks = 0, skipped = 0;
  NSMutableArray *nodes = [NSMutableArray array]; NSUInteger count = 0;
  if (![self lineDrawCollect:snapshot nodes:nodes depth:0 count:&count viewport:viewport checks:&checks skipped:&skipped filter:filter]) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Observation limits exceeded" traceback:nil]);
  }
  NSTimeInterval collected = NSProcessInfo.processInfo.systemUptime;
  NSString *after = [self lineDrawActiveIdentity][@"bundleId"] ?: @"unknown";
  if (![after isEqualToString:bundle]) { return FBResponseWithObject(@{@"schema": @1, @"bundleId": after, @"ready": @NO}); }
  CGRect r = snapshot.frame;
  return FBResponseWithObject(@{
    @"schema": @1, @"bundleId": bundle, @"ready": @YES,
    @"nativeSeconds": @(NSProcessInfo.processInfo.systemUptime-began),
    @"snapshotSeconds": @(captured-began), @"collectSeconds": @(collected-captured),
    @"visibilityChecks": @(checks), @"geometrySkipped": @(skipped),
    @"tree": @{@"type": @"Application", @"isVisible": @YES, @"isEnabled": @YES,
      @"rect": @{@"x": @(r.origin.x), @"y": @(r.origin.y), @"width": @(r.size.width), @"height": @(r.size.height)},
      @"children": nodes}
  });
}
'''
    source=source.replace('\n@end',method+'\n@end')
    path.write_text(source)

if __name__=='__main__':
    patch(sys.argv[1])
