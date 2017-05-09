//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ShowGroupMembersViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "SignalsViewController.h"
#import "Signal-Swift.h"
#import "UIUtil.h"
#import "ViewControllerUtils.h"
#import <AddressBookUI/AddressBookUI.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>

@import ContactsUI;

NS_ASSUME_NONNULL_BEGIN

@interface ShowGroupMembersViewController () <ContactsViewHelperDelegate, CNContactViewControllerDelegate>

@property (nonatomic, readonly) TSGroupThread *thread;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic, nullable) NSSet<NSString *> *memberRecipientIds;

@end

#pragma mark -

@implementation ShowGroupMembersViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}


- (void)commonInit
{
    _contactsViewHelper = [ContactsViewHelper new];
    _contactsViewHelper.delegate = self;
}

- (void)configWithThread:(TSGroupThread *)thread
{

    _thread = thread;

    OWSAssert(self.thread);
    OWSAssert(self.thread.groupModel);
    OWSAssert(self.thread.groupModel.groupMemberIds);

    self.memberRecipientIds = [NSSet setWithArray:self.thread.groupModel.groupMemberIds];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // HACK otherwise CNContactViewController Navbar is shown as black.
    // RADAR rdar://28433898 http://www.openradar.me/28433898
    // CNContactViewController incompatible with opaque navigation bar
    [self.navigationController.navigationBar setTranslucent:YES];

    self.title = _thread.groupModel.groupName;

    [self updateTableContents];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // In case we're dismissing a CNContactViewController which requires default system appearance
    [UIUtil applySignalAppearence];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSAssert(self.thread);

    OWSTableContents *contents = [OWSTableContents new];

    __weak ShowGroupMembersViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;

    // Group Members

    OWSTableSection *section = [OWSTableSection new];

    NSMutableSet *memberRecipientIds = [self.memberRecipientIds mutableCopy];
    [memberRecipientIds removeObject:[helper localNumber]];
    for (NSString *recipientId in [memberRecipientIds.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            ShowGroupMembersViewController *strongSelf = weakSelf;
            OWSAssert(strongSelf);

            ContactTableViewCell *cell = [ContactTableViewCell new];
            SignalAccount *signalAccount = [helper signalAccountForRecipientId:recipientId];
            BOOL isBlocked = [helper isRecipientIdBlocked:recipientId];
            if (isBlocked) {
                cell.accessoryMessage
                    = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
            }

            if (signalAccount) {
                [cell configureWithSignalAccount:signalAccount contactsManager:helper.contactsManager];
            } else {
                [cell configureWithRecipientId:recipientId contactsManager:helper.contactsManager];
            }

            return cell;
        }
                             customRowHeight:[ContactTableViewCell rowHeight]
                             actionBlock:^{
                                 [weakSelf didSelectRecipientId:recipientId];
                             }]];
    }
    [contents addSection:section];

    self.contents = contents;
}

- (void)didSelectRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    ContactsViewHelper *helper = self.contactsViewHelper;
    SignalAccount *signalAccount = [helper signalAccountForRecipientId:recipientId];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *contactInfoTitle = signalAccount
        ? NSLocalizedString(@"GROUP_MEMBERS_VIEW_CONTACT_INFO", @"Button label for the 'show contact info' button")
        : NSLocalizedString(
              @"GROUP_MEMBERS_ADD_CONTACT_INFO", @"Button label to add information to an unknown contact");
    [actionSheetController addAction:[UIAlertAction actionWithTitle:contactInfoTitle
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction *_Nonnull action) {
                                                                [self showContactInfoViewForRecipientId:recipientId];
                                                            }]];

    BOOL isBlocked;
    if (signalAccount) {
        isBlocked = [helper isRecipientIdBlocked:signalAccount.recipientId];
        if (isBlocked) {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON",
                                                             @"Button label for the 'unblock' button")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils
                                                         showUnblockSignalAccountActionSheet:signalAccount
                                                                          fromViewController:self
                                                                             blockingManager:helper.blockingManager
                                                                             contactsManager:helper.contactsManager
                                                                             completionBlock:^(BOOL ignore) {
                                                                                 [self updateTableContents];
                                                                             }];
                                                 }]];
        } else {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON",
                                                             @"Button label for the 'block' button")
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils
                                                         showBlockSignalAccountActionSheet:signalAccount
                                                                        fromViewController:self
                                                                           blockingManager:helper.blockingManager
                                                                           contactsManager:helper.contactsManager
                                                                           completionBlock:^(BOOL ignore) {
                                                                               [self updateTableContents];
                                                                           }];
                                                 }]];
        }
    } else {
        isBlocked = [helper isRecipientIdBlocked:recipientId];
        if (isBlocked) {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON",
                                                             @"Button label for the 'unblock' button")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils
                                                         showUnblockPhoneNumberActionSheet:recipientId
                                                                        fromViewController:self
                                                                           blockingManager:helper.blockingManager
                                                                           contactsManager:helper.contactsManager
                                                                           completionBlock:^(BOOL ignore) {
                                                                               [self updateTableContents];
                                                                           }];
                                                 }]];
        } else {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON",
                                                             @"Button label for the 'block' button")
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils
                                                         showBlockPhoneNumberActionSheet:recipientId
                                                                      fromViewController:self
                                                                         blockingManager:helper.blockingManager
                                                                         contactsManager:helper.contactsManager
                                                                         completionBlock:^(BOOL ignore) {
                                                                             [self updateTableContents];
                                                                         }];
                                                 }]];
        }
    }

    if (!isBlocked) {
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"GROUP_MEMBERS_SEND_MESSAGE",
                                                         @"Button label for the 'send message to group member' button")
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *_Nonnull action) {
                                                 [self showConversationViewForRecipientId:recipientId];
                                             }]];
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"GROUP_MEMBERS_CALL",
                                                         @"Button label for the 'call group member' button")
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *_Nonnull action) {
                                                 [self callMember:recipientId];
                                             }]];
    }

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)showContactInfoViewForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    ContactsViewHelper *helper = self.contactsViewHelper;
    SignalAccount *signalAccount = [helper signalAccountForRecipientId:recipientId];

    if (!helper.contactsManager.isSystemContactsAuthorized) {
        UIAlertController *alertController = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"EDIT_CONTACT_WITHOUT_CONTACTS_PERMISSION_ALERT_TITLE", comment
                                                       : @"Alert title for when the user has just tried to edit a "
                                                         @"contacts after declining to give Signal contacts "
                                                         @"permissions")
                             message:NSLocalizedString(@"EDIT_CONTACT_WITHOUT_CONTACTS_PERMISSION_ALERT_BODY", comment
                                                       : @"Alert body for when the user has just tried to edit a "
                                                         @"contacts after declining to give Signal contacts "
                                                         @"permissions")
                      preferredStyle:UIAlertControllerStyleAlert];

        [alertController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"AB_PERMISSION_MISSING_ACTION_NOT_NOW",
                                                         @"Button text to dismiss missing contacts permission alert")
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];

        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OPEN_SETTINGS_BUTTON",
                                                                      @"Button text which opens the settings app")
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              [[UIApplication sharedApplication] openSystemSettings];
                                                          }]];

        [self presentViewController:alertController animated:YES completion:nil];
        return;
    }
    
    CNContactViewController *_Nullable contactViewController;
    if (signalAccount) {
        CNContact *_Nullable cnContact = signalAccount.contact.cnContact;
        if (cnContact) {
            contactViewController = [CNContactViewController viewControllerForContact:cnContact];
        }
    }

    if (!contactViewController) {
        CNMutableContact *newContact = [CNMutableContact new];
        CNPhoneNumber *phoneNumber = [CNPhoneNumber phoneNumberWithStringValue:recipientId];
        CNLabeledValue<CNPhoneNumber *> *labeledPhoneNumber = [CNLabeledValue labeledValueWithLabel:CNLabelPhoneNumberMain
                                                                             value:phoneNumber];
        newContact.phoneNumbers = @[labeledPhoneNumber];
        
        contactViewController = [CNContactViewController viewControllerForNewContact:newContact];
    }

    contactViewController.delegate = self;
    contactViewController.allowsActions = NO;
    contactViewController.allowsEditing = YES;
    contactViewController.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(dismissPressed)];

    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:contactViewController];
    [self presentViewController:navigationController animated:YES completion:nil];


    // HACK otherwise CNContactViewController Navbar is shown as black.
    // RADAR rdar://28433898 http://www.openradar.me/28433898
    // CNContactViewController incompatible with opaque navigation bar
    [UIUtil applyDefaultSystemAppearence];
}

- (void)showConversationViewForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [Environment messageIdentifier:recipientId withCompose:YES];
}

- (void)callMember:(NSString *)recipientId
{
    [Environment callUserWithIdentifier:recipientId];
}

- (void)dismissPressed
{
    DDLogDebug(@"%@ %s", self.tag, __PRETTY_FUNCTION__);
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    // FIXME new names are not immediately chown.
    // doing some debugging, it seems that even though [self.tableView reloadData] is called
    // we don't see subsequent invocations of `cellForIndexpath:` unless the items are scrolled off screen.
    
    [self updateTableContents];
}

- (BOOL)shouldHideLocalNumber
{
    return YES;
}

#pragma mark - CNContactViewControllerDelegate

- (void)contactViewController:(CNContactViewController *)viewController
       didCompleteWithContact:(nullable CNContact *)contact
{
    DDLogDebug(@"%@ done editing contact.", self.tag);
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
