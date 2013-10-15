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
@property (nonatomic) UILabel *curPayoutLabel, *curPayout;
@property (nonatomic) UILabel *curPositionLabel, *curPosition;
@property (nonatomic) UILabel *curScoreLabel, *curScore;

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
        ent.text = NSLocalizedString(@"Max Entries:", nil);
        [self addSubview:ent];
        
        _entries = [[UILabel alloc] initWithFrame:CGRectMake(95, 81, 180, 18)];
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
        
        _cost = [[UILabel alloc] initWithFrame:CGRectMake(95, 99, 180, 18)];
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
        
        _payouts = [[UILabel alloc] initWithFrame:CGRectMake(95, 117, 180, 18)];
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
        
        _curScoreLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 135, 220, 18)];
        _curScoreLabel.backgroundColor = [UIColor clearColor];
        _curScoreLabel.textColor = [FFStyle greyTextColor];
        _curScoreLabel.font = [FFStyle regularFont:14];
        _curScoreLabel.text = NSLocalizedString(@"Score:", nil);
        [self addSubview:_curScoreLabel];
        
        _curScore = [[UILabel alloc] initWithFrame:CGRectMake(95, 135, 180, 18)];
        _curScore.backgroundColor = [UIColor clearColor];
        _curScore.textColor = [FFStyle darkGreyTextColor];
        _curScore.font = [FFStyle regularFont:14];
        [self addSubview:_curScore];
        
        _curPositionLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 153, 220, 18)];
        _curPositionLabel.backgroundColor = [UIColor clearColor];
        _curPositionLabel.textColor = [FFStyle greyTextColor];
        _curPositionLabel.font = [FFStyle regularFont:14];
        _curPositionLabel.text = NSLocalizedString(@"Position:", nil);
        [self addSubview:_curPositionLabel];
        
        _curPosition = [[UILabel alloc] initWithFrame:CGRectMake(95, 153, 180, 18)];
        _curPosition.backgroundColor = [UIColor clearColor];
        _curPosition.textColor = [FFStyle darkGreyTextColor];
        _curPosition.font = [FFStyle regularFont:14];
        [self addSubview:_curPosition];
        
        _curPayoutLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 171, 220, 18)];
        _curPayoutLabel.backgroundColor = [UIColor clearColor];
        _curPayoutLabel.textColor = [FFStyle greyTextColor];
        _curPayoutLabel.font = [FFStyle regularFont:14];
        _curPayoutLabel.text = NSLocalizedString(@"Payout:", nil);
        [self addSubview:_curPayoutLabel];
        
        _curPayout = [[UILabel alloc] initWithFrame:CGRectMake(95, 171, 180, 18)];
        _curPayout.backgroundColor = [UIColor clearColor];
        _curPayout.textColor = [FFStyle darkGreyTextColor];
        _curPayout.font = [FFStyle regularFont:14];
        [self addSubview:_curPayout];
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

- (void)setRoster:(FFRoster *)roster
{
    _roster = roster;
    if (_roster && [_roster.live integerValue]) {
        // show the shit
        _curPayout.hidden = _curPayoutLabel.hidden = NO;
        _curScore.hidden = _curScoreLabel.hidden = NO;
        _curPosition.hidden = _curPositionLabel.hidden = NO;
        
        _curScore.text = (roster.score == nil ? @"0" : [roster.score description]);
        _curPayout.text = (roster.amountPaid != nil ? [roster.amountPaid description] : @"0");
        _curPosition.text = [NSString stringWithFormat:@"%@ %@ %@",
                             (roster.contestRank == nil ? @"0" : roster.contestRank),
                             NSLocalizedString(@"of", nil),
                             (_contest.maxEntries == nil ? @"0" : _contest.maxEntries)];
    } else {
        // hide the shit
        _curPayout.hidden = _curPayoutLabel.hidden = YES;
        _curScore.hidden = _curScoreLabel.hidden = YES;
        _curPosition.hidden = _curPositionLabel.hidden = YES;
    }
}

@end
