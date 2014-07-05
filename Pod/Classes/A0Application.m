//
//  A0Application.m
//  Pods
//
//  Created by Hernan Zalazar on 7/4/14.
//
//

#import "A0Application.h"

@implementation A0Application

- (instancetype)initWithJSONDictionary:(NSDictionary *)JSONDict {
    self = [super init];
    if (self) {
        NSAssert(JSONDict, @"Must supply non empty JSON dictionary");
        NSString *identifier = JSONDict[@"id"];
        NSString *tenant = JSONDict[@"tenant"];
        NSString *authorize = JSONDict[@"authorize"];
        NSString *callback = JSONDict[@"callback"];
        NSArray *array = JSONDict[@"strategies"];
        NSMutableArray *strategies = [@[] mutableCopy];
        [array enumerateObjectsUsingBlock:^(NSDictionary *strategyDict, NSUInteger idx, BOOL *stop) {
            [strategies addObject:strategyDict[@"name"]];
        }];
        NSAssert(identifier.length > 0, @"Must have a valid name");
        NSAssert(tenant.length > 0, @"Must have a valid tenant");
        NSAssert(authorize.length > 0, @"Must have a valid auhorize URL");
        NSAssert(callback.length > 0, @"Must have a valid callback URL");
        NSAssert(strategies.count > 0, @"Must have at least 1 strategy");
        _identifier = identifier;
        _tenant = tenant;
        _authorizeURL = [NSURL URLWithString:authorize];
        _callbackURL = [NSURL URLWithString:callback];
        _strategies = [NSArray arrayWithArray:strategies];
    }
    return self;
}

- (BOOL)hasDatabaseConnection {
    return [self.strategies containsObject:@"auth0"];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<A0Application id = '%@'; tenant = '%@' strategies = %@>", self.identifier, self.tenant, self.strategies];
}
@end