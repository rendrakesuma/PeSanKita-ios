//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"
#import <UIKit/UIKit.h>

@class TSThread;
typedef NS_ENUM(NSInteger, CellState) { kArchiveState, kInboxState };

@interface SignalsViewController : OWSViewController

// TODO: Remove this property.
@property (nonatomic) BOOL newlyRegisteredUser;

- (instancetype)initWithCellType:(CellState)cellState;

- (void)presentThread:(TSThread *)thread
    keyboardOnViewAppearing:(BOOL)keyboardOnViewAppearing
        callOnViewAppearing:(BOOL)callOnViewAppearing;

- (void)composeNew;

- (void)presentTopLevelModalViewController:(UIViewController *)viewController
                          animateDismissal:(BOOL)animateDismissal
                       animatePresentation:(BOOL)animatePresentation;
- (void)pushTopLevelViewController:(UIViewController *)viewController
                  animateDismissal:(BOOL)animateDismissal
               animatePresentation:(BOOL)animatePresentation;

@end
