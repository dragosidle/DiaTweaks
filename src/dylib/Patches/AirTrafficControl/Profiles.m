#import "Patches/AirTrafficControl/AirTrafficControl.h"

@interface NSObject (DPAirSwiftFields)
- (id)safeSwiftValueForKey:(NSString *)key;  // AXCoreUtilities: reads Swift properties the Obj-C runtime hides.
@end

// The sidebar's switcher keeps an item per profile and the tab strip's indicator a dot, each by Swift SpaceID, which
// describes itself as the ID. Profile Emoji keys its emoji by the same IDs, so they're stable across launches.
static NSView *DPSwitcherIn(NSWindow *window) {
    NSView *switcher = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaSpaceSwitcher); });
    if (switcher) return switcher;
    return DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaPageIndicatorDot); }).superview;
}

static NSDictionary *DPItemsOf(NSView *switcher) {
    if (!switcher) return nil;
    id items = [switcher safeSwiftValueForKey:DPIsKind(switcher, DPDiaSpaceSwitcher) ? @"itemViews" : @"dotViews"];
    return [items isKindOfClass:NSDictionary.class] ? items : nil;
}

static NSString *DPNameOf(NSView *item, NSString *profileID) {
    NSString *name = item.accessibilityLabel.length ? item.accessibilityLabel : item.toolTip;
    return name.length ? name : profileID;
}

NSArray<NSDictionary *> *DPProfiles(void) {
    for (NSWindow *window in NSApp.orderedWindows) {
        NSDictionary *items = DPItemsOf(DPSwitcherIn(window));
        if (!items.count) continue;
        NSArray *keys = [items.allKeys sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [@(NSMinX(((NSView *)items[a]).frame)) compare:@(NSMinX(((NSView *)items[b]).frame))];
        }];
        NSMutableArray<NSDictionary *> *profiles = [NSMutableArray new];
        for (id key in keys) [profiles addObject:@{ @"id" : [key description], @"name" : DPNameOf(items[key], [key description]) }];
        return profiles;
    }
    return @[];
}

NSString *DPWindowProfile(NSWindow *window) {
    NSView *switcher = DPSwitcherIn(window);
    NSDictionary *items = DPItemsOf(switcher);
    if (!items.count) return nil;
    id focused = [switcher safeSwiftValueForKey:@"focusedSpaceID"];  // The tab strip's indicator says which dot is lit.
    if (focused) return [focused description];
    for (id key in items) if ([[items[key] safeSwiftValueForKey:@"isSelected"] boolValue]) return [key description];
    return nil;
}

NSWindow *DPWindowOnProfile(NSString *profileID) {
    for (NSWindow *window in NSApp.orderedWindows) if ([DPWindowProfile(window) isEqualToString:profileID]) return window;
    return nil;
}

// Dia switches profiles when their item is clicked, so the click is replayed on it through the window, as the mouse would send it.
static void DPClick(NSView *item) {
    if ([item isKindOfClass:NSControl.class]) return (void)[(NSControl *)item performClick:nil];
    NSWindow *window = item.window;
    NSPoint point = [item convertPoint:NSMakePoint(NSMidX(item.bounds), NSMidY(item.bounds)) toView:nil];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:now
                                   windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:now + 0.05
                                 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0];
    [window sendEvent:down];
    [window sendEvent:up];
}

void DPSwitchToProfile(NSWindow *window, NSString *profileID, void (^done)(BOOL switched)) {
    if ([DPWindowProfile(window) isEqualToString:profileID]) return done(YES);
    NSDictionary *items = DPItemsOf(DPSwitcherIn(window));
    NSView *item = nil;
    for (id key in items) if ([[key description] isEqualToString:profileID]) item = items[key];
    if (!item) return done(NO);
    DPClick(item);
    // The switch animates and the switcher reports it late, so the window is watched until it shows the profile, for up
    // to four seconds, then given a moment to settle.
    __block int polls = 0;
    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) {
        BOOL switched = [DPWindowProfile(window) isEqualToString:profileID];
        if (!switched && ++polls < 80) return;
        [timer invalidate];
        DPTrace(@"the switcher showed %@ after %d ms", switched ? @"the profile" : @"no change", polls * 50);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ done(switched); });
    }];
}
