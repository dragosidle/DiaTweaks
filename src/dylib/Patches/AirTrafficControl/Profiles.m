#import "Patches/AirTrafficControl/AirTrafficControl.h"

// The sidebar's switcher keeps an item per profile and the tab strip's indicator a dot, each by Swift SpaceID, which
// describes itself as the ID. Profile Emoji keys its emoji by the same IDs, so they're stable across launches.
NSView *DPSwitcherIn(NSWindow *window) {
    NSView *switcher = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaSpaceSwitcher); });
    if (switcher) return switcher;
    return DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaPageIndicatorDot); }).superview;
}

NSDictionary *DPSwitcherItems(NSView *switcher) {
    if (!switcher) return nil;
    id items = [switcher safeSwiftValueForKey:DPIsKind(switcher, DPDiaSpaceSwitcher) ? @"itemViews" : @"dotViews"];
    return [items isKindOfClass:NSDictionary.class] ? items : nil;
}

// The sidebar's items carry the profile's name as itemTitle; anything else falls back to what accessibility says, then the ID.
static NSString *DPNameOf(NSView *item, NSString *profileID) {
    id title = [item safeSwiftValueForKey:@"itemTitle"];
    NSString *name = [title isKindOfClass:NSString.class] ? title : nil;
    if (!name.length) name = item.accessibilityLabel.length ? item.accessibilityLabel : item.toolTip;
    return name.length ? name : profileID;
}

NSArray<NSDictionary *> *DPProfiles(void) {
    for (NSWindow *window in NSApp.orderedWindows) {
        NSDictionary *items = DPSwitcherItems(DPSwitcherIn(window));
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

NSString *DPProfileName(NSString *profileID) {
    for (NSDictionary *profile in DPProfiles()) if ([profile[@"id"] isEqualToString:profileID]) return profile[@"name"];
    return nil;
}

// Dia titles a browser window "Profile: Page", which also says which profile it shows.
static NSString *DPProfileInTitle(NSWindow *window) {
    for (NSDictionary *profile in DPProfiles())
        if ([window.title hasPrefix:[profile[@"name"] stringByAppendingString:@": "]]) return profile[@"id"];
    return nil;
}

NSString *DPWindowProfile(NSWindow *window) {
    NSView *switcher = DPSwitcherIn(window);
    NSDictionary *items = DPSwitcherItems(switcher);
    if (!items.count) return nil;
    id focused = [switcher safeSwiftValueForKey:@"focusedSpaceID"];  // The tab strip's indicator says which dot is lit.
    if (focused) return [focused description];
    NSString *selected = nil;
    for (id key in items) if ([[items[key] safeSwiftValueForKey:@"isSelected"] boolValue]) selected = [key description];
    return DPProfileInTitle(window) ?: selected;
}

NSWindow *DPWindowOnProfile(NSString *profileID) {
    for (NSWindow *window in NSApp.orderedWindows) if ([DPWindowProfile(window) isEqualToString:profileID]) return window;
    return nil;
}
