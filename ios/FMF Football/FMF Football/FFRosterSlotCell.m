//
//  FFRosterSlotCell.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/26/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFRosterSlotCell.h"
#import <AFNetworking/UIImageView+AFNetworking.h>


@interface FFRosterSlotCell ()

@property (nonatomic) UIImageView *img;
@property (nonatomic) UILabel *emptyPosition;
@property (nonatomic) UILabel *name;
@property (nonatomic) UILabel *team;
@property (nonatomic) UILabel *price;
@property (nonatomic) UIButton *select;
@property (nonatomic) UIButton *trade;
@property (nonatomic) UILabel *diff;
@property (nonatomic) UILabel *points;

@property (nonatomic) id player;
@property (nonatomic) FFRoster *roster;
@property (nonatomic) FFMarket *market;

@end


@implementation FFRosterSlotCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:.94 alpha:1];
        _img = [[UIImageView alloc] initWithFrame:CGRectMake(15, 11, 57, 57)];
        _img.backgroundColor = [UIColor clearColor];
        _img.image = [UIImage imageNamed:@"rosterslotempty.png"];
        _img.contentMode = UIViewContentModeScaleAspectFill;
        _img.clipsToBounds = YES;
        [self.contentView addSubview:_img];
        
        UIImageView *mask = [[UIImageView alloc] initWithFrame:CGRectMake(15, 11, 57, 57)];
        mask.backgroundColor = [UIColor clearColor];
        mask.image = [UIImage imageNamed:@"playerselectmask.png"];
        [self addSubview:mask];
        
        _team = [[UILabel alloc] initWithFrame:CGRectMake(82, 32, 140, 16)];
        _team.backgroundColor = [UIColor clearColor];
        _team.font = [FFStyle regularFont:13];
        _team.textColor = [FFStyle greyTextColor];
        [self.contentView addSubview:_team];
        
        _name = [[UILabel alloc] initWithFrame:CGRectMake(82, 13, 140, 16)];
        _name.backgroundColor = [UIColor clearColor];
        _name.font = [FFStyle regularFont:17];
        _name.textColor = [FFStyle darkGreyTextColor];
        [self.contentView addSubview:_name];
        
        _price = [[UILabel alloc] initWithFrame:CGRectMake(82, 50, 80, 16)];
        _price.backgroundColor = [UIColor clearColor];
        _price.font = [FFStyle mediumFont:14];
        _price.textColor = [FFStyle darkGreyTextColor];
        [self.contentView addSubview:_price];
        
        _diff = [[UILabel alloc] initWithFrame:CGRectMake(162, 50, 80, 16)];
        _diff.backgroundColor = [UIColor clearColor];
        _diff.font = [FFStyle regularFont:14];
        _diff.textColor = [FFStyle brightGreen];
        [self.contentView addSubview:_diff];
        
        _emptyPosition = [[UILabel alloc] initWithFrame:CGRectMake(82, 0, 80, self.frame.size.height)];
        _emptyPosition.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        _emptyPosition.backgroundColor = [UIColor clearColor];
        _emptyPosition.font = [FFStyle regularFont:19];
        _emptyPosition.textColor = [FFStyle greyTextColor];
        [self.contentView addSubview:_emptyPosition];
        
        _select = [FFStyle coloredButtonWithText:NSLocalizedString(@"Select", nil)
                                           color:[FFStyle brightGreen]
                                     borderColor:[FFStyle white]];
        _select.frame = CGRectMake(224, 21, 80, 38);
        [_select addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_select];
        
        _trade = [FFStyle coloredButtonWithText:NSLocalizedString(@"Trade", nil)
                                           color:[FFStyle brightRed]
                                     borderColor:[FFStyle white]];
        _trade.frame = CGRectMake(224, 21, 80, 38);
        _trade.hidden = YES;
        [_trade addTarget:self action:@selector(replace:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_trade];
        
        _points = [[UILabel alloc] initWithFrame:CGRectMake(200, 0, 20, self.contentView.frame.size.height)];
        _points.backgroundColor = [UIColor clearColor];
        _points.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        _points.font = [FFStyle regularFont:16];
        _points.hidden = YES;
        [self.contentView addSubview:_points];
        
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(7, 78, 306, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:.5];
        [self.contentView addSubview:sep];
        
        sep = [[UIView alloc] initWithFrame:CGRectMake(7, 79, 306, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:1 alpha:.5];
        [self.contentView addSubview:sep];
    }
    return self;
}

- (BOOL)isInPlay
{
    return (![self.market.state isEqualToString:@"published"] && ![self.roster.state isEqualToString:@"in_progress"]);
}

- (BOOL)marketStarted
{
    return [self.market.startedAt compare:[NSDate date]] == NSOrderedDescending;
}

- (void)setPlayer:(id)player andRoster:(FFRoster *)roster andMarket:(FFMarket *)market
{
    _player = player;
    _roster = roster;
    _market = market;
    
    if ([player isKindOfClass:[NSString class]]) {
        // it's an empty slot
        _emptyPosition.text = (NSString *)player;
        _img.image = [UIImage imageNamed:@"rosterslotempty.png"];
        _emptyPosition.hidden = NO;
        _select.hidden = NO;
        _name.hidden = YES;
        _team.hidden = YES;
        _price.hidden = YES;
        _trade.hidden = YES;
        _diff.hidden = YES;
    } else {
        _emptyPosition.hidden = YES;
        _select.hidden = YES;
        _name.hidden = NO;
        _team.hidden = NO;
        _price.hidden = NO;
        
        _name.text = player[@"name"];
        NSString *ppg = [player[@"ppg"] isEqual:[NSNull null]] ? @"0" : player[@"ppg"];
        _team.text = [NSString stringWithFormat:@"%@ %@ %@ PPG", player[@"position"], player[@"team"], ppg];
        
        if ([player[@"headshot_url"] isKindOfClass:[NSString class]]) {
            [_img setImageWithURL:[NSURL URLWithString:player[@"headshot_url"]]
                 placeholderImage:[UIImage imageNamed:@"rosterslotempty.png"]];
        } else {
            _img.image = [UIImage imageNamed:@"rosterslotempty.png"];
        }
        if ([self isInPlay]) {
            _price.text = [NSString stringWithFormat:@"$%@", player[@"purchase_price"]];
            _price.frame = CGRectMake(82, 50, [_price.text sizeWithFont:_price.font].width, 16);
            _diff.hidden = NO;
            
            double sellPrice = [player[@"sell_price"] doubleValue],
               purchasePrice = [player[@"purchase_price"] doubleValue];
            double diff =  ((sellPrice - purchasePrice) / purchasePrice) * 100;
            
            _diff.text = [NSString stringWithFormat:@"%.2lf%%", diff];
            _diff.frame = CGRectMake(CGRectGetMaxX(_price.frame)+5, 50, 80, 16);
            
            if ((sellPrice - purchasePrice) < 0) {
                _diff.textColor = [FFStyle brightRed];
            } else {
                _diff.textColor = [FFStyle brightGreen];
            }
        } else {
            _diff.hidden = YES;
            _price.text = [NSString stringWithFormat:@"$%@", player[@"buy_price"]];
            _price.frame = CGRectMake(82, 50, 80, 16);
        }
        
        _trade.hidden = !(([_market.state isEqualToString:@"published"]
                          || [_market.state isEqualToString:@"opened"])
                          && ![player[@"locked"] boolValue]);
        
        if ([self marketStarted]) {
            _points.hidden = NO;
            int score = [player[@"score"] integerValue];
            
            if (score) {
                _points.textColor = [FFStyle darkerColorForColor:[FFStyle brightBlue]];
            } else {
                _points.textColor = [FFStyle greyTextColor];
            }
            _points.text = [NSString stringWithFormat:@"%d", score];
        }
    }
}

- (void)select:(UIButton *)sender
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(rosterCellSelectPlayer:)]) {
        [self.delegate rosterCellSelectPlayer:self];
    }
}

- (void)replace:(UIButton *)sender
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(rosterCellReplacePlayer:)]) {
        [self.delegate rosterCellReplacePlayer:self];
    }
}

@end
