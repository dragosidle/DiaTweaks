// Tools for writing patches, on with `defaults write com.diapatches devTools -bool YES` and a relaunch of Dia.
#import "StdPatch/StdPatch.h"

void DPInstallDevTools(void);
NSString *DPDescribeViews(NSView *root);  // One line per view: class, frame, label, rounded corners, and whether it's hidden.
void DPTraceLayoutLoops(void);            // Writes what keeps a window's layout dirty to layout-loops.txt beside the dylib.
void DPListenForProbes(void);             // Probe.m: writes classes, Swift fields and the menus to probe.txt for scripts/probe.
