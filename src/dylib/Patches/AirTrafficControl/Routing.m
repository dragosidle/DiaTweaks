// Where a link goes, and how it gets there: a window on the right profile, or the front window switched to it, then Dia opens it.
#import "Patches/AirTrafficControl/AirTrafficControl.h"
#import <objc/message.h>
#import <os/log.h>

static NSMutableDictionary<NSString *, NSDate *> *DPHandedOver;  // URL → when it was handed back to Dia, which the hooks then let by.
static const NSTimeInterval DPHandOverSeconds = 3;

void DPTrace(NSString *format, ...) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] boolForKey:@"devTools"]; });
    if (!on) return;
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    os_log(OS_LOG_DEFAULT, "DiaPatches ATC: %{public}@", line);
}

void DPForgetOld(NSMutableDictionary<NSString *, NSDate *> *times, NSTimeInterval seconds) {
    for (NSString *key in times.allKeys) if (-times[key].timeIntervalSinceNow >= seconds) [times removeObjectForKey:key];
}

BOOL DPRoutingReady(void) { return DPAirTrafficControl.on && DPProfiles().count >= 2; }

static BOOL DPProfileExists(NSString *profileID) {
    for (NSDictionary *profile in DPProfiles()) if ([profile[@"id"] isEqualToString:profileID]) return YES;
    return NO;
}

static BOOL DPWasHandedOver(NSURL *url) {
    NSDate *when = DPHandedOver[url.absoluteString ?: @""];
    return when && -when.timeIntervalSinceNow < DPHandOverSeconds;
}

NSString *DPDestination(NSURL *url, NSURL *from, BOOL external) {
    if (![url isKindOfClass:NSURL.class]) return nil;
    if (DPWasHandedOver(url)) return nil;  // On its way to where it was sent.
    if (!DPRoutingReady()) {
        DPTrace(@"%@ stays: %@", url, DPAirTrafficControl.on ? @"fewer than two profiles found" : @"off");
        return nil;
    }
    if (!external && !DPAirTrafficInsideDia.on) {
        DPTrace(@"%@ stays: only links from other apps are routed", url);
        return nil;
    }
    NSString *profile = DPRoutedProfile(url);
    if (!profile && external) profile = DPDefaultProfile();
    if (!profile.length) {
        DPTrace(@"%@ stays: no route", url);
        return nil;
    }
    if (!DPProfileExists(profile)) {
        DPTrace(@"%@ stays: its profile %@ is gone", url, profile);
        return nil;
    }
    if (!external && [DPRoutedProfile(from) isEqualToString:profile]) {
        DPTrace(@"%@ stays: the page %@ is already in that domain", url, from);
        return nil;
    }
    NSWindow *window = NSApp.keyWindow ?: NSApp.orderedWindows.firstObject;
    NSString *current = DPWindowProfile(window);
    if ([current isEqualToString:profile]) {
        DPTrace(@"%@ stays: the window is on %@ already", url, profile);
        return nil;
    }
    DPTrace(@"%@ goes to profile %@ (the window shows %@)", url, profile, current ?: @"no profile");
    return profile;
}

// Dia opens links from other apps in the front window's profile, so once a window shows the right one, the link takes that road.
static void DPHandOver(NSURL *url) {
    DPForgetOld(DPHandedOver, DPHandOverSeconds);
    DPHandedOver[url.absoluteString ?: @""] = NSDate.date;
    SEL open = @selector(application:openURLs:);
    if ([NSApp.delegate respondsToSelector:open]) ((void (*)(id, SEL, id, NSArray *))objc_msgSend)(NSApp.delegate, open, NSApp, @[ url ]);
    else [NSWorkspace.sharedWorkspace openURL:url];
}

void DPOpenInProfile(NSURL *url, NSString *profileID) {
    if (!DPHandedOver) DPHandedOver = [NSMutableDictionary new];
    NSWindow *window = DPWindowOnProfile(profileID);
    for (NSWindow *candidate in NSApp.orderedWindows) if (!window && DPWindowProfile(candidate)) window = candidate;
    if (!window) {
        DPTrace(@"no browser window to switch, handing %@ to Dia", url);
        return DPHandOver(url);
    }
    DPTrace(@"switching \"%@\" (on %@) to %@", window.title, DPWindowProfile(window) ?: @"no profile", profileID);
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    DPSwitchToProfile(window, profileID, ^(BOOL switched) {
        if (!switched) os_log(OS_LOG_DEFAULT, "DiaPatches: couldn't switch to profile %{public}@ for %{public}@", profileID, url);
        DPTrace(@"%@, handing %@ to Dia", switched ? @"switched" : @"not switched", url);
        DPHandOver(url);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DPTrace(@"half a second on, the window shows %@ and the key window is \"%@\"", DPWindowProfile(window) ?: @"no profile", NSApp.keyWindow.title);
        });
    });
}
