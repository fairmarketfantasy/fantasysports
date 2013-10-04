//
//  FFUserBitView.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFUserBitView.h"
#import <AFNetworking/UIImageView+AFNetworking.h>

@interface FFUserBitView ()

@property (nonatomic) UIImageView *image;
@property (nonatomic) UILabel *name;
@property (nonatomic) UILabel *memberSince;
@property (nonatomic) UILabel *points;
@property (nonatomic) UILabel *wins;

@end

@implementation FFUserBitView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        UIImageView *avatarMask = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"avatarmask.png"]];
        avatarMask.frame = CGRectMake(235, 25, 70, 70);
        avatarMask.contentMode = UIViewContentModeCenter;
        avatarMask.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        avatarMask.backgroundColor = [UIColor clearColor];
        
        _image = [[UIImageView alloc] initWithFrame:avatarMask.frame];
        _image.contentMode = UIViewContentModeScaleAspectFill;
        _image.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        _image.image = [UIImage imageNamed:@"defaultuser.png"];
        
        [self addSubview:_image];
        [self addSubview:avatarMask];
        
        _name = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 205, 35)];
        _name.backgroundColor = [UIColor clearColor];
        _name.font = [FFStyle regularFont:21];
        _name.textColor = [FFStyle darkGreyTextColor];
        _name.text = @"username";
        [self addSubview:_name];
        
        _memberSince = [[UILabel alloc] initWithFrame:CGRectMake(15, 35, 205, 30)];
        _memberSince.backgroundColor = [UIColor clearColor];
        _memberSince.font = [FFStyle regularFont:13];
        _memberSince.textColor = [FFStyle greyTextColor];
        _memberSince.text = @"Member Since 9/10/2013";
        [self addSubview:_memberSince];
        
        _points = [[UILabel alloc] initWithFrame:CGRectMake(15, 54, 205, 30)];
        _points.backgroundColor = [UIColor clearColor];
        _points.font = [FFStyle regularFont:13];
        _points.textColor = [FFStyle greyTextColor];
        _points.text = @"234,503 points";
        [self addSubview:_points];
        
        _wins = [[UILabel alloc] initWithFrame:CGRectMake(15, 70, 205, 35)];
        _wins.backgroundColor = [UIColor clearColor];
        _wins.font = [FFStyle regularFont:13];
        _wins.textColor = [FFStyle greyTextColor];
        _wins.text = @"23 wins (0.492 win %)";
        [self addSubview:_wins];
        
        _finishInProgressRoster = [FFStyle coloredButtonWithText:NSLocalizedString(@"In Progress Roster", nil)
                                                           color:[FFStyle brightOrange] borderColor:[FFStyle white]];
        _finishInProgressRoster.frame = CGRectMake(15, 110, 290, 35);
        [self addSubview:_finishInProgressRoster];
    }
    return self;
}

- (void)setUser:(FFUser *)user
{
    _user = user;
    
    NSDateFormatter *df = [NSDateFormatter new];
    [df setDateStyle:NSDateFormatterMediumStyle];
    
    _name.text = user.name;
    _memberSince.text = [NSString stringWithFormat:@"Member Since %@", [df stringFromDate:_user.joinDate]];
    _points.text = [NSString stringWithFormat:@"%d points", [_user.totalPoints integerValue]];
    _wins.text = [NSString stringWithFormat:@"%d wins (%.2f win %%)",
                  [_user.totalWins integerValue], [_user.winPercentile floatValue]];
    NSURL *url = [NSURL URLWithString:_user.imageUrl];
    [_image setImageWithURL:url placeholderImage:[UIImage imageNamed:@"defaultuser.png"]];
    
    if (user.inProgressRoster != nil) {
        _finishInProgressRoster.hidden = NO;
//        self.frame = CGRectMake(0, 0, 320, 162);
    } else {
        _finishInProgressRoster.hidden = YES;
//        self.frame = CGRectMake(0, 0, 320, 122);
    }
}

@end
