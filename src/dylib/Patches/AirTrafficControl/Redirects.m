// Redirects: a site that sends its visitors on to a routed one, like twitter.com to x.com. The hooks only see where a load
// starts, and Dia neither calls its server-redirect callback nor says where a navigation began. So each hook notes the
// address it let a page load, and when the page commits somewhere routed differently, that's a redirect to route.
#import "Patches/AirTrafficControl/AirTrafficControl.h"

static NSMapTable<id, NSDictionary *> *DPLoads;                  // A page → {url, before, when}: the load let through.
static NSMutableDictionary<NSString *, NSDate *> *DPFromOutside;  // URLs from other apps, which route even with the switch off.

void DPNoteFromOutside(NSURL *url) {
    if (!DPFromOutside) DPFromOutside = [NSMutableDictionary new];
    DPForgetOld(DPFromOutside, 30);
    DPFromOutside[url.absoluteString ?: @""] = NSDate.date;
}

static BOOL DPCameFromOutside(NSURL *url) {
    NSDate *when = DPFromOutside[url.absoluteString ?: @""];
    return when && -when.timeIntervalSinceNow < 30;
}

void DPNoteLoad(id page, NSURL *url, NSURL *before) {
    if (!page || !url) return;
    if (!DPLoads) DPLoads = [NSMapTable weakToStrongObjectsMapTable];
    NSMutableDictionary *load = [@{ @"url" : url, @"when" : NSDate.date } mutableCopy];
    if (before) load[@"before"] = before;
    [DPLoads setObject:load forKey:page];
}

static NSURL *DPAddressOf(id page) {
    id url = nil;
    @try { url = [page valueForKey:@"url"]; } @catch (NSException *e) {}
    return [url isKindOfClass:NSURL.class] ? url : nil;
}

// A commit that leaves the page's address as it was is one of its frames; the page's own lands on a new address.
static void DPWebContent_didCommit(id self, SEL _cmd, id page, id navigation) {
    DPCallOriginal(DPWebContent_didCommit, self, page, navigation);
    NSDictionary *load = [DPLoads objectForKey:page];
    NSURL *url = DPAddressOf(page), *from = load[@"url"], *before = load[@"before"];
    if (!load || !url || [url isEqual:before]) return;
    [DPLoads removeObjectForKey:page];
    if (-[load[@"when"] timeIntervalSinceNow] > 30) return;
    NSString *routed = DPRoutedProfile(url);
    if (!routed || [routed isEqualToString:DPRoutedProfile(from) ?: @""]) return;  // Not routed, or routed from the start.
    DPTrace(@"%@ redirected to %@", from, url);
    NSString *profile = DPDestination(url, from, DPCameFromOutside(from));
    if (!profile) return;
    dispatch_async(dispatch_get_main_queue(), ^{ DPOpenInProfile(url, profile); });
    // The tab is left as it was: a new or blank one closes, one that was on a page goes back to it.
    BOOL blank = !before || [before.scheme isEqualToString:@"dia"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id history = [page respondsToSelector:@selector(navigationController)] ? [page valueForKey:@"navigationController"] : nil;
        if (blank && [page respondsToSelector:@selector(close)]) {
            DPTrace(@"closing the tab the redirect landed in");
            [page performSelector:@selector(close)];
        } else if ([history respondsToSelector:@selector(goBack)]) {
            DPTrace(@"taking the tab back to %@", before);
            [history performSelector:@selector(goBack)];
        }
    });
}

void DPInstallRedirects(void) {
    DPHook(DPDiaWebContent, @selector(webContents:didCommitNavigation:), (IMP)DPWebContent_didCommit);
}
