//
//  FFContestView.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFContestView.h"

@interface FFContestView ()

@property (nonatomic) UILabel *title;
@property (nonatomic) UILabel *subtitle;
@property (nonatomic) UILabel *guaranteedPayout;
@property (nonatomic) UILabel *entries;
@property (nonatomic) UILabel *cost;
@property (nonatomic) UILabel *payouts;
@property (nonatomic) UIImageView *img;

@end

@implementation FFContestView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
//        self.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
        _title = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 320, 25)];
        _title.backgroundColor = [UIColor clearColor];
        _title.textColor = [FFStyle darkGreyTextColor];
        _title.font = [FFStyle blockFont:24];
        [self addSubview:_title];
        
        _subtitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 35, 200, 40)];
        _subtitle.backgroundColor = [UIColor clearColor];
        _subtitle.numberOfLines = 2;
        _subtitle.lineBreakMode = NSLineBreakByWordWrapping;
        _subtitle.textColor = [FFStyle greyTextColor];
        _subtitle.font = [FFStyle regularFont:13];
        [self addSubview:_subtitle];
        
        UILabel *ent = [[UILabel alloc] initWithFrame:CGRectMake(15, 81, 220, 18)];
        ent.backgroundColor = [UIColor clearColor];
        ent.textColor = [FFStyle greyTextColor];
        ent.font = [FFStyle regularFont:14];
        ent.text = NSLocalizedString(@"Entries:", nil);
        [self addSubview:ent];
        
        _entries = [[UILabel alloc] initWithFrame:CGRectMake(82, 81, 220, 18)];
        _entries.backgroundColor = [UIColor clearColor];
        _entries.textColor = [FFStyle darkGreyTextColor];
        _entries.font = [FFStyle regularFont:14];
        [self addSubview:_entries];
        
        UILabel *cst = [[UILabel alloc] initWithFrame:CGRectMake(15, 99, 220, 18)];
        cst.backgroundColor = [UIColor clearColor];
        cst.textColor = [FFStyle greyTextColor];
        cst.font = [FFStyle regularFont:14];
        cst.text = NSLocalizedString(@"Cost:", nil);
        [self addSubview:cst];
        
        _cost = [[UILabel alloc] initWithFrame:CGRectMake(82, 99, 220, 18)];
        _cost.backgroundColor = [UIColor clearColor];
        _cost.textColor = [FFStyle darkGreyTextColor];
        _cost.font = [FFStyle regularFont:14];
        [self addSubview:_cost];
        
        UILabel *po = [[UILabel alloc] initWithFrame:CGRectMake(15, 117, 220, 18)];
        po.backgroundColor = [UIColor clearColor];
        po.textColor = [FFStyle greyTextColor];
        po.font = [FFStyle regularFont:14];
        po.text = NSLocalizedString(@"Payouts:", nil);
        [self addSubview:po];
        
        _payouts = [[UILabel alloc] initWithFrame:CGRectMake(82, 117, 220, 18)];
        _payouts.backgroundColor = [UIColor clearColor];
        _payouts.textColor = [FFStyle darkGreyTextColor];
        _payouts.font = [FFStyle regularFont:14];
        [self addSubview:_payouts];
        
        _img = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 35, 35)];
        _img.backgroundColor = [UIColor clearColor];
        _img.contentMode = UIViewContentModeScaleAspectFit;
        _img.center = CGPointMake(270, 48);
        _img.alpha = .5;
        _img.userInteractionEnabled = NO;
        [self addSubview:_img];
        
        UIImageView *_circle = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"contestcircle.png"]];
        _circle.frame = CGRectMake(0, 0, 69, 69);
        _circle.center = CGPointMake(270, 48);
        _circle.userInteractionEnabled = NO;
        [self addSubview:_circle];
    }
    return self;
}

- (void)setContest:(FFContestType *)contest
{
    _contest = contest;
    
    _title.text = contest.name;
    _subtitle.text = contest.contestDescription;
    _entries.text = [contest.maxEntries description];
    _cost.text = [contest.buyIn description];
    _payouts.text = contest.payoutDescription;
    
    NSString *iconUrl = [NSString stringWithFormat:@"%@%@",
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:SBApiBaseURLKey],
                         contest.iconUrl];
    [_img setImageWithURL:[NSURL URLWithString:iconUrl]];
}

- (void)setMarket:(FFMarket *)market
{
    _market = market;
}

@end
