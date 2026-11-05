#import "Patches/AirTrafficControl/AirTrafficControl.h"

static void DPApplyAirTrafficControl(DPPatch *patch) {}  // Nothing on screen changes with the switch, so there's nothing to animate.

DP_PATCH(DPAirTrafficControl) {
    .key = @"airTrafficControl",
    .order = 5,
    .title = @"Air Traffic Control",
    .detail = @"Open each site in the profile you choose, like Arc’s Air Traffic Control. A link to a routed site opens in that profile "
              @"wherever it comes from, another app or a page in Dia, and Dia switches to the profile when it has to.",
    .hint = @"Needs two or more profiles. Add them in Settings › Profiles.",
    .symbol = @"airplane.departure airplane",
    .tint = @"systemIndigoColor",
    .section = @"Features",
    .classes = DPClasses(DPDiaSpaceSwitcher, DPDiaSpaceSwitcherItem, DPDiaPageIndicatorDot, DPDiaWebContents),
    .rows = DPAirTrafficRows,
    .install = DPInstallRouting,
    .apply = DPApplyAirTrafficControl,
    .verify = DPVerifyRouting,
};
