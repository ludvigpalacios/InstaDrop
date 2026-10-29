//
//  AppDelegate.h
//  InstaDrop
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong, nonatomic) NSStatusItem *statusBar;

@property (strong) IBOutlet NSMenu *statusMenu;

@end