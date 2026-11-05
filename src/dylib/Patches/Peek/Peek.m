#import "Patches/Peek/Peek.h"
#import "Patches/AirTrafficControl/AirTrafficControl.h"

static NSURL *DPPeekHovered;
static __weak id DPPeekHoveredPage;

// The profile Air Traffic Control opens `url` in instead, or nil: asked as it asks from the link's page, and from none,
// as the card's own load reaches its hook.
static NSString *DPPeekRouted(NSURL *url, id source) {
    id from = [(NSObject *)source valueForKey:@"url"];
    return DPDestination(url, [from isKindOfClass:NSURL.class] ? from : nil, NO) ?: DPDestination(url, nil, NO);
}

// Shift-click peeks a link that would open elsewhere. With new-tab links on, a plain click peeks a link Dia opens in a
// new tab itself (`fromDia`), while ⌘ still makes a tab, and a page the site opens, which keeps window.opener, stays Dia's.
// A link Air Traffic Control routes is peeked in that profile, named by `profile`, if the window has a browser for it,
// and inside a card only if it's the card's own. Any other it routes itself.
static BOOL DPPeekWanted(NSInteger disposition, BOOL fromDia, NSURL *url, id source, NSString **profile) {
    *profile = nil;
    if (!DPPeek.on || DPPeekGiving()) return NO;
    NSEventModifierFlags mods = NSEvent.modifierFlags;
    BOOL command = mods & NSEventModifierFlagCommand, newTabs = DPPeekNewTabs(), wanted;
    BOOL elsewhere = disposition == DPForegroundTab || disposition == DPBackgroundTab || disposition == DPPopup || disposition == DPNewWindow;
    if (mods & NSEventModifierFlagShift) wanted = elsewhere && !(newTabs && command);
    else wanted = newTabs && fromDia && disposition == DPForegroundTab && !command;
    if (!wanted) return NO;
    NSString *routed = DPPeekRouted(url, source);
    if (!routed) return YES;
    DPPeekCard *card = DPPeekCardShowing(source);
    BOOL ours = card ? [routed isEqualToString:card.profile] : DPPeekBrowserFor(NSApp.keyWindow, routed) != nil;
    if (ours) *profile = routed;
    return ours;
}

static void DPPeekOpenLater(id delegate, id source, NSURL *url, NSString *profile) {
    NSWindow *window = NSApp.keyWindow;
    NSPoint origin = NSEvent.mouseLocation;
    dispatch_async(dispatch_get_main_queue(), ^{ DPPeekOpen(window, url, origin, delegate, source, profile); });
}

static void DPWebContent_didCreate(id self, SEL _cmd, id webContents, id newWebContent, NSURL *url, NSInteger disposition) {
    NSString *profile = nil;
    if (!DPPeekWanted(disposition, NO, url, webContents, &profile) || !(DPPeekShows(webContents) || DPPeekCanOpen(webContents)))
        return (void)DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, disposition);
    // Air Traffic Control's hook sits below this one and would route a routed address too, so Dia is handed a blank one.
    NSURL *ignored = profile ? [NSURL URLWithString:@"about:blank"] : url;
    DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, ignored, (NSInteger)DPIgnoreAction);
    if (DPPeekShows(webContents)) return DPPeekLoad(webContents, url);
    DPPeekOpenLater(self, webContents, url, profile);
}

static NSInteger DPWebContent_decidePolicy(id self, SEL _cmd, id webContents, id action) {
    NSURL *url = [action valueForKey:@"url"];
    NSString *profile = nil;
    if (!DPPeekWanted([[action valueForKey:@"navigationDisposition"] integerValue], YES, url, webContents, &profile))
        return DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
    if (DPPeekShows(webContents)) return DPCurrentTab;
    if (!DPPeekCanOpen(webContents)) return DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
    DPPeekOpenLater(self, webContents, url, profile);
    return DPIgnoreAction;
}

static void DPPeekLookAhead(void) {
    NSEventModifierFlags mods = NSEvent.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask & ~NSEventModifierFlagCapsLock;
    id page = DPPeekHoveredPage;
    if (DPPeek.on && mods == NSEventModifierFlagShift && DPPeekHovered && page && !DPPeekShows(page) && DPPeekCanOpen(page)
        && !DPPeekRouted(DPPeekHovered, page))
        DPPeekWarm(NSApp.keyWindow, page, DPPeekHovered);
    else DPPeekCool();
}

static void DPWebContent_status(id self, SEL _cmd, id webContents, NSString *text) {
    DPCallOriginal(DPWebContent_status, self, webContents, text);
    NSURL *url = text.length ? [NSURL URLWithString:text] : nil;
    if (!url && webContents != DPPeekHoveredPage) return;  // Other pages, the warm one included, clear their own.
    DPPeekHovered = [@[ @"http", @"https" ] containsObject:url.scheme.lowercaseString] ? url : nil;
    DPPeekHoveredPage = webContents;
    DPPeekLookAhead();
}

static void DPInstallPeek(void) {
    DPPeekInstallPages();
    DPOnLaunch(^{
        DPHook(DPDiaWebContent, @selector(webContents:didCreateNewWebContent:targetURL:disposition:), (IMP)DPWebContent_didCreate);
        DPHook(DPDiaWebContent, @selector(webContents:decidePolicyForNavigationAction:), (IMP)DPWebContent_decidePolicy);
        DPHook(DPDiaWebContent, @selector(webContents:didChangeStatusText:), (IMP)DPWebContent_status);
    });
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged handler:^NSEvent *(NSEvent *event) {
        DPPeekLookAhead();
        return event;
    }];
}

static NSString *DPVerifyPeek(DPPatch *patch) {
    Class delegate = objc_getClass(DPDiaWebContent);
    if (class_getMethodImplementation(delegate, @selector(webContents:decidePolicyForNavigationAction:)) != (IMP)DPWebContent_decidePolicy)
        return @"link clicks don't reach Peek";
    if (class_getMethodImplementation(delegate, @selector(webContents:didCreateNewWebContent:targetURL:disposition:)) != (IMP)DPWebContent_didCreate)
        return @"new windows don't reach Peek";
    return nil;
}

DP_PATCH(DPPeek) {
    .key = @"peek",
    .order = 104,
    .title = @"Peek on Shift-Click",
    .detail = @"Shift-click a link to preview it in a card over the page, like Arc. Click outside, press Escape or ⌘W to close it, ⌘O to open it as a tab, or use the buttons beside it. Turn on Also peek links that open a new tab to peek those with a plain click too; ⌘-click still opens a tab.",
    .symbol = @"eye.fill",
    .tint = @"systemMintColor",
    .section = @"Links",
    .classes = DPClasses(DPDiaBrowserContext, DPDiaWebContents, DPDiaWebContentsConfiguration, DPDiaContentPane),
    .install = DPInstallPeek,
    .verify = DPVerifyPeek,
    .rows = DPPeekSettingsRows,
    .hint = @"Tip: right after Dia starts, open or switch to any tab once to start Peek.",
};
