// Switching a window to a profile, the way Dia does it: its Window menu lists every profile, with ⌃1, ⌃2 and so on.
// Without such an item, the sidebar's switcher gets the click it handles itself.
#import "Patches/AirTrafficControl/AirTrafficControl.h"

// The profile's item is found by its place in the switcher, not its name: the tab strip's dots have no names, and two
// profiles can share one.
static BOOL DPChooseInMenu(NSString *profileID) {
    NSArray<NSDictionary *> *profiles = DPProfiles();
    NSUInteger index = [profiles indexOfObjectPassingTest:^BOOL(NSDictionary *profile, NSUInteger i, BOOL *stop) {
        return [profile[@"id"] isEqualToString:profileID];
    }];
    NSMenuItem *item = index == NSNotFound ? nil : DPProfileMenuItem(index);
    if (!item) return NO;
    NSMenu *parent = item.menu.supermenu;  // The submenu has no title of its own; its item in the Window menu does.
    NSString *menuName = [parent itemAtIndex:[parent indexOfItemWithSubmenu:item.menu]].title;
    DPTrace(@"choosing \"%@\" (⌃%lu) in Dia's \"%@\" menu", item.title, (unsigned long)index + 1, menuName);
    [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]];
    return YES;
}

// The switcher decides which item a click was on from the event's location, so it gets one at the item's middle.
static BOOL DPClickInSwitcher(NSWindow *window, NSString *profileID) {
    NSView *switcher = DPSwitcherIn(window);
    NSDictionary *items = DPSwitcherItems(switcher);
    NSView *item = nil;
    for (id key in items) if ([[key description] isEqualToString:profileID]) item = items[key];
    if (!item) return NO;
    DPTrace(@"clicking the switcher's item for %@", profileID);
    NSPoint point = [item convertPoint:NSMakePoint(NSMidX(item.bounds), NSMidY(item.bounds)) toView:nil];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:now
                                   windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:now + 0.05
                                 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0];
    [switcher mouseDown:down];
    [switcher mouseUp:up];
    return YES;
}

void DPSwitchToProfile(NSWindow *window, NSString *profileID, void (^done)(BOOL switched)) {
    if ([DPWindowProfile(window) isEqualToString:profileID]) return done(YES);
    if (!DPChooseInMenu(profileID) && !DPClickInSwitcher(window, profileID)) {
        DPTrace(@"no menu item or switcher item for %@", profileID);
        return done(NO);
    }
    // The switch animates and the switcher reports it late, so the window is watched until it shows the profile, for up
    // to four seconds, then given a moment to settle.
    __block int polls = 0;
    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) {
        BOOL switched = [DPWindowProfile(window) isEqualToString:profileID];
        if (!switched && ++polls < 80) return;
        [timer invalidate];
        DPTrace(@"the window showed %@ after %d ms", switched ? @"the profile" : @"no change", polls * 50);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ done(switched); });
    }];
}
