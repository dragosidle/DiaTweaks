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

// Dia's menu bar lists every profile, in the switcher's order, in a submenu of the Window menu (titled after the front
// profile, with Manage Profiles… under them): Dragos ⌃1, Work ⌃2, … The last one also answers to ⌃9.
static NSMenu *DPProfileMenu(void) {
    for (NSMenuItem *top in NSApp.mainMenu.itemArray)
        for (NSMenuItem *item in top.submenu.itemArray) {
            NSMenu *menu = item.submenu;
            for (NSMenuItem *entry in menu.itemArray)
                if ([entry.keyEquivalent isEqualToString:@"1"] && entry.keyEquivalentModifierMask == NSEventModifierFlagControl) return menu;
        }
    return nil;
}

NSMenuItem *DPProfileMenuItem(NSUInteger index) {
    NSString *key = [NSString stringWithFormat:@"%lu", (unsigned long)index + 1];
    for (NSMenuItem *entry in DPProfileMenu().itemArray)
        if ([entry.keyEquivalent isEqualToString:key] && entry.keyEquivalentModifierMask == NSEventModifierFlagControl) return entry;
    return nil;
}

// The sidebar's items carry the profile's name as itemTitle. The tab strip's dots carry nothing, so their names come from
// the menu by position, then from what accessibility says, then the ID.
static NSString *DPNameOf(NSView *item, NSString *profileID, NSUInteger index) {
    id title = [item safeSwiftValueForKey:@"itemTitle"];
    NSString *name = [title isKindOfClass:NSString.class] ? title : nil;
    if (!name.length) name = DPProfileMenuItem(index).title;
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
        for (id key in keys)
            [profiles addObject:@{ @"id" : [key description], @"name" : DPNameOf(items[key], [key description], profiles.count) }];
        return profiles;
    }
    return @[];
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
