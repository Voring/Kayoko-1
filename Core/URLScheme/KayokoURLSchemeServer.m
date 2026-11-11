//
//  KayokoURLSchemeServer.m
//  Kayoko
//

#import "KayokoURLSchemeServer.h"

#import "KayokoURLSchemeHandler.h"
#import "KayokoURLSchemeProtocol.h"

#import <UIKit/UIKit.h>
#import <notify.h>

@interface KayokoURLSchemeServer ()

@property(nonatomic, assign) int requestToken;

- (void)handleIncomingRequest;
- (void)writeResponseWithRequestIdentifier:(nullable NSString *)requestIdentifier
                                   handled:(BOOL)handled
                                     error:(nullable NSError *)error;
@end

@implementation KayokoURLSchemeServer

#pragma mark - Lifecycle

+ (instancetype)sharedServer {
    static KayokoURLSchemeServer *server;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      server = [[self alloc] init];
    });
    return server;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _requestToken = -1;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Serving

- (BOOL)start {
    if ([self requestToken] != -1) {
        return YES;
    }

    __weak typeof(self) weakSelf = self;
    int token = -1;
    uint32_t status = notify_register_dispatch([kKayokoURLSchemeRequestNotificationName UTF8String], &token,
                                               dispatch_get_main_queue(), ^(int notificationToken) {
                                                 (void)notificationToken;
                                                 typeof(self) strongSelf = weakSelf;
                                                 if (!strongSelf) {
                                                     return;
                                                 }
                                                 [strongSelf handleIncomingRequest];
                                               });
    if (status != NOTIFY_STATUS_OK) {
        return NO;
    }

    [self setRequestToken:token];
    return YES;
}

- (void)stop {
    if ([self requestToken] != -1) {
        notify_cancel([self requestToken]);
        [self setRequestToken:-1];
    }
}

#pragma mark - Requests

- (void)handleIncomingRequest {
    NSDictionary<NSString *, id> *request = KayokoURLSchemeReadMessage(KayokoURLSchemeRequestPath());
    NSString *requestIdentifier = request[kKayokoURLSchemeMessageKeyRequestIdentifier];
    NSString *urlString = request[kKayokoURLSchemeMessageKeyURL];
    if (![requestIdentifier isKindOfClass:[NSString class]] || [requestIdentifier length] == 0 ||
        ![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) {
        return;
    }

    NSURL *URL = [NSURL URLWithString:urlString];
    if (!URL) {
        [self writeResponseWithRequestIdentifier:requestIdentifier
                                          handled:NO
                                            error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown,
                                                                           @"Malformed URL")];
        return;
    }

    NSString *source = request[kKayokoURLSchemeMessageKeySource];
    if (![source isKindOfClass:[NSString class]]) {
        source = nil;
    }

    BOOL accepted = [[KayokoURLSchemeHandler sharedHandler]
        handleURL:URL
          source:source
      completion:^(KayokoURLSchemeResult result, NSError *error) {
        [self writeResponseWithRequestIdentifier:requestIdentifier
                                          handled:(result == KayokoURLSchemeResultSuccess)
                                            error:error];
      }];

    if (!accepted) {
        [self writeResponseWithRequestIdentifier:requestIdentifier
                                          handled:NO
                                            error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown,
                                                                           @"Unsupported URL scheme")];
    }
}

- (void)writeResponseWithRequestIdentifier:(NSString *)requestIdentifier
                                   handled:(BOOL)handled
                                     error:(NSError *)error {
    NSMutableDictionary<NSString *, id> *response = [NSMutableDictionary dictionary];
    if ([requestIdentifier length] > 0) {
        [response setObject:requestIdentifier forKey:kKayokoURLSchemeMessageKeyRequestIdentifier];
    }
    [response setObject:@(handled) forKey:kKayokoURLSchemeMessageKeyHandled];
    if (error) {
        [response setObject:@{
            kKayokoURLSchemeMessageKeyErrorDomain : [error domain] ?: kKayokoURLSchemeErrorDomain,
            kKayokoURLSchemeMessageKeyErrorCode : @([error code]),
            kKayokoURLSchemeMessageKeyErrorMessage : [error localizedDescription] ?: @"Unknown error"
        }
                      forKey:kKayokoURLSchemeMessageKeyError];
    }

    NSError *writeError = nil;
    if (!KayokoURLSchemeWriteMessage(response, KayokoURLSchemeResponsePath(), &writeError)) {
        NSLog(@"Kayoko: unable to write URL scheme response: %@", writeError);
        return;
    }

    notify_post([kKayokoURLSchemeResponseNotificationName UTF8String]);
}

@end
