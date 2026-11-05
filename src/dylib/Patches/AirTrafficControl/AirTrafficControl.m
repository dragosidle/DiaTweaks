#import "Patches/AirTrafficControl/AirTrafficControl.h"

static void DPApplyAirTrafficControl(DPPatch *patch) {}  // Nothing on screen changes with the switch, so there's nothing to animate.

DP_PATCH(DPAirTrafficControl) {
    .key = @"airTrafficControl",
    .order = 103,  // First in Links: it ties Peek on Shift-Click on title length, which sorts a section before order does.
    .title = @"Air Traffic Control",
    .detail = @"Open each site in the profile you choose, like Arc’s Air Traffic Control. A link to a routed site opens in that profile "
              @"wherever it comes from, another app or a page in Dia, and Dia switches to the profile when it has to.",
    .hint = @"Needs two or more profiles. Add them in Settings › Profiles.",
    .symbol = @"airplane.departure airplane",
    .tint = @"systemMintColor",
    .section = @"Links",
    .classes = DPClasses(DPDiaSpaceSwitcher, DPDiaSpaceSwitcherItem, DPDiaPageIndicatorDot, DPDiaWebContents),
    .rows = DPAirTrafficRows,
    .install = DPInstallRouting,
    .apply = DPApplyAirTrafficControl,
    .verify = DPVerifyRouting,
};

// Off, only links from other apps are routed, as Arc does it. On, so are clicks in pages and addresses typed into a tab.
DP_PATCH(DPAirTrafficInsideDia) {
    .key = @"airTrafficInsideDia",
    .defaultOn = YES,
    .title = @"Route Links Inside Dia Too",
    .detail = @"Also send a routed site to its profile when its link is clicked on a page or typed into a tab. "
              @"Off, only links from other apps are routed.",
    .requires = @"airTrafficControl",
    .apply = DPApplyAirTrafficControl,
};
